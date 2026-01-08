package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	gormlogger "gorm.io/gorm/logger"
	"go.mau.fi/whatsmeow/store"
	"go.mau.fi/whatsmeow/store/sqlstore"
	waLog "go.mau.fi/whatsmeow/util/log"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/config"
	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
	"github.com/clippy-oss/homie/whatsapp-bridge/internal/repository"
	"github.com/clippy-oss/homie/whatsapp-bridge/internal/service"
	grpcTransport "github.com/clippy-oss/homie/whatsapp-bridge/internal/transport/grpc"
	mcpTransport "github.com/clippy-oss/homie/whatsapp-bridge/internal/transport/mcp"
)

func main() {
	// Load configuration
	cfg := config.Load()

	log.Printf("WhatsApp Bridge starting...")
	log.Printf("Database: %s", cfg.DatabasePath)
	log.Printf("gRPC address: %s", cfg.GRPCAddress)
	log.Printf("MCP address: %s", cfg.MCPAddress)

	// Initialize logger for whatsmeow
	waLogger := waLog.Stdout("WhatsApp", "INFO", true)

	// Initialize database
	db, err := initDatabase(cfg.DatabasePath)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}

	// Initialize whatsmeow device store
	ctx := context.Background()
	device, container, err := initDeviceStore(ctx, cfg.DatabasePath, waLogger)
	if err != nil {
		log.Fatalf("Failed to initialize device store: %v", err)
	}
	_ = container // Keep container reference to prevent GC

	// Initialize repositories
	msgRepo := repository.NewMessageRepository(db)
	chatRepo := repository.NewChatRepository(db)
	contactRepo := repository.NewContactRepository(db)

	// Initialize event bus
	eventBus := domain.NewEventBus()

	// Initialize WhatsApp service
	waSvc := service.NewWhatsAppService(
		device,
		eventBus,
		msgRepo,
		chatRepo,
		contactRepo,
		service.WhatsAppServiceConfig{
			MediaDownloadPath: cfg.MediaPath,
		},
		waLogger,
	)

	// Initialize message service
	msgSvc := service.NewMessageService(msgRepo, chatRepo, waSvc)

	// Initialize gRPC server
	grpcServer := grpcTransport.NewServer(
		waSvc,
		msgSvc,
		grpcTransport.ServerConfig{
			Address: cfg.GRPCAddress,
		},
	)

	// Initialize MCP SSE server
	mcpServer := mcpTransport.NewServer(
		msgSvc,
		waSvc,
		mcpTransport.ServerConfig{
			Address: cfg.MCPAddress,
		},
	)

	// Error channel for server errors
	errCh := make(chan error, 2)

	// Start gRPC server
	go func() {
		log.Printf("Starting gRPC server on %s", cfg.GRPCAddress)
		if err := grpcServer.Start(); err != nil {
			errCh <- fmt.Errorf("gRPC server error: %w", err)
		}
	}()

	// Start MCP SSE server
	go func() {
		log.Printf("Starting MCP SSE server on %s", cfg.MCPAddress)
		if err := mcpServer.Start(); err != nil {
			errCh <- fmt.Errorf("MCP server error: %w", err)
		}
	}()

	// Auto-connect if device is already registered
	if device.ID != nil {
		log.Printf("Device registered, attempting auto-connect...")
		go func() {
			time.Sleep(1 * time.Second) // Brief delay to let servers start
			if err := waSvc.Connect(context.Background()); err != nil {
				log.Printf("Auto-connect failed: %v", err)
			} else {
				log.Printf("Auto-connected to WhatsApp")
			}
		}()
	} else {
		log.Printf("No device registered. Use gRPC GetPairingQR to pair a device.")
	}

	// Print ready message for subprocess coordination
	fmt.Println("ready")

	// Wait for shutdown signal
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	select {
	case err := <-errCh:
		log.Printf("Server error: %v", err)
	case sig := <-sigCh:
		log.Printf("Received signal %v, shutting down...", sig)
	}

	// Graceful shutdown
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	log.Printf("Disconnecting WhatsApp...")
	waSvc.Disconnect()

	log.Printf("Stopping gRPC server...")
	grpcServer.Stop()

	log.Printf("Stopping MCP server...")
	if err := mcpServer.Stop(ctx); err != nil {
		log.Printf("MCP server stop error: %v", err)
	}

	log.Printf("Shutdown complete")
}

func initDatabase(dbPath string) (*gorm.DB, error) {
	db, err := gorm.Open(sqlite.Open(dbPath), &gorm.Config{
		Logger: gormlogger.Default.LogMode(gormlogger.Warn),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// Enable WAL mode for better concurrency
	db.Exec("PRAGMA journal_mode=WAL")

	// Auto-migrate models
	err = db.AutoMigrate(
		&repository.MessageModel{},
		&repository.ChatModel{},
		&repository.ContactModel{},
	)
	if err != nil {
		return nil, fmt.Errorf("failed to migrate database: %w", err)
	}

	return db, nil
}

func initDeviceStore(ctx context.Context, dbPath string, logger waLog.Logger) (*store.Device, *sqlstore.Container, error) {
	// Use a separate database file for whatsmeow to avoid schema conflicts
	waDBPath := dbPath[:len(dbPath)-3] + "_wa.db"

	container, err := sqlstore.New(ctx, "sqlite3", "file:"+waDBPath+"?_foreign_keys=on", logger)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create sqlstore container: %w", err)
	}

	device, err := container.GetFirstDevice(ctx)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get device: %w", err)
	}

	return device, container, nil
}
