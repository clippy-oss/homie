package main

import (
	"context"
	"flag"
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

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/cli"
	"github.com/clippy-oss/homie/whatsapp-bridge/internal/config"
	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
	"github.com/clippy-oss/homie/whatsapp-bridge/internal/repository"
	"github.com/clippy-oss/homie/whatsapp-bridge/internal/service"
	grpcTransport "github.com/clippy-oss/homie/whatsapp-bridge/internal/transport/grpc"
	mcpTransport "github.com/clippy-oss/homie/whatsapp-bridge/internal/transport/mcp"
)

// RunMode defines how the application runs
type RunMode string

const (
	RunModeServer      RunMode = "server"
	RunModeInteractive RunMode = "interactive"
	RunModeHeadless    RunMode = "headless"
)

func main() {
	// Parse command-line flags
	mode := flag.String("mode", "server", "Run mode: server, interactive, or headless")
	flag.Parse()

	// Load configuration
	cfg := config.Load()

	// Initialize logger for whatsmeow (quiet for CLI modes)
	var waLogger waLog.Logger
	if RunMode(*mode) == RunModeServer {
		waLogger = waLog.Stdout("WhatsApp", "INFO", true)
	} else {
		waLogger = waLog.Stdout("WhatsApp", "ERROR", true)
	}

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

	// Initialize event bus
	eventBus := domain.NewEventBus()

	// Initialize WhatsApp service
	// Note: Contacts are stored by whatsmeow's built-in ContactStore, not in our repository
	waSvc := service.NewWhatsAppService(
		device,
		eventBus,
		msgRepo,
		chatRepo,
		service.WhatsAppServiceConfig{
			MediaDownloadPath: cfg.MediaPath,
		},
		waLogger,
	)

	// Initialize message service
	msgSvc := service.NewMessageService(msgRepo, chatRepo, waSvc)

	switch RunMode(*mode) {
	case RunModeInteractive:
		runInteractiveMode(ctx, waSvc, msgSvc, device)
	case RunModeHeadless:
		runHeadlessMode(ctx, waSvc, msgSvc, device)
	default:
		runServerMode(ctx, cfg, waSvc, msgSvc, device)
	}
}

func runServerMode(ctx context.Context, cfg *config.Config, waSvc *service.WhatsAppService, msgSvc *service.MessageService, device *store.Device) {
	log.Printf("WhatsApp Bridge starting...")
	log.Printf("Database: %s", cfg.DatabasePath)
	log.Printf("gRPC address: %s", cfg.GRPCAddress)
	log.Printf("MCP address: %s", cfg.MCPAddress)

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
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	log.Printf("Disconnecting WhatsApp...")
	waSvc.Disconnect()

	log.Printf("Stopping gRPC server...")
	grpcServer.Stop()

	log.Printf("Stopping MCP server...")
	if err := mcpServer.Stop(shutdownCtx); err != nil {
		log.Printf("MCP server stop error: %v", err)
	}

	log.Printf("Shutdown complete")
}

func runInteractiveMode(ctx context.Context, waSvc *service.WhatsAppService, msgSvc *service.MessageService, device *store.Device) {
	// Auto-connect if device is already registered
	if device.ID != nil {
		if err := waSvc.Connect(ctx); err != nil {
			log.Printf("Auto-connect failed: %v", err)
		}
	}

	// Create CLI handler and interactive CLI
	handler := cli.NewCommandHandler(waSvc, msgSvc)
	interactiveCLI := cli.NewInteractiveCLI(handler)

	// Setup signal handling
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigCh
		cancel()
	}()

	// Run interactive CLI
	if err := interactiveCLI.Run(ctx); err != nil && err != context.Canceled {
		log.Printf("CLI error: %v", err)
	}

	// Cleanup
	waSvc.Disconnect()
}

func runHeadlessMode(ctx context.Context, waSvc *service.WhatsAppService, msgSvc *service.MessageService, device *store.Device) {
	// Auto-connect if device is already registered
	if device.ID != nil {
		if err := waSvc.Connect(ctx); err != nil {
			// Will report via JSON response
		}
	}

	// Create CLI handler and headless CLI
	handler := cli.NewCommandHandler(waSvc, msgSvc)
	headlessCLI := cli.NewHeadlessCLI(handler)

	// Setup signal handling
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigCh
		cancel()
	}()

	// Run headless CLI
	if err := headlessCLI.Run(ctx); err != nil && err != context.Canceled {
		log.Printf("CLI error: %v", err)
	}

	// Cleanup
	waSvc.Disconnect()
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
	// Note: Contacts are stored by whatsmeow's built-in ContactStore (whatsmeow_contacts table)
	err = db.AutoMigrate(
		&repository.MessageModel{},
		&repository.ChatModel{},
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
