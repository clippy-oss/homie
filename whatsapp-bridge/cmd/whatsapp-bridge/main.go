package main

import (
	"context"
	"fmt"
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
	"github.com/clippy-oss/homie/whatsapp-bridge/internal/logger"
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
	// Load configuration (also handles flag parsing)
	cfg := config.Load()

	// Initialize structured logger
	logLevel := cfg.LogLevel
	if RunMode(cfg.Mode) != RunModeServer {
		logLevel = "error" // Quiet for CLI modes
	}
	logger.Init(logLevel)
	log := logger.Module("main")

	// Create whatsmeow-compatible logger
	waLogger := logger.NewWALogger("whatsapp")

	// Initialize database
	db, err := initDatabase(cfg.DatabasePath)
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to initialize database")
	}

	// Initialize whatsmeow device store
	ctx := context.Background()
	device, container, err := initDeviceStore(ctx, cfg.DatabasePath, waLogger)
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to initialize device store")
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

	switch RunMode(cfg.Mode) {
	case RunModeInteractive:
		runInteractiveMode(ctx, waSvc, msgSvc, device)
	case RunModeHeadless:
		runHeadlessMode(ctx, waSvc, msgSvc, device)
	default:
		runServerMode(ctx, cfg, waSvc, msgSvc, device)
	}
}

func runServerMode(ctx context.Context, cfg *config.Config, waSvc *service.WhatsAppService, msgSvc *service.MessageService, device *store.Device) {
	log := logger.Module("main")

	log.Info().Msg("WhatsApp Bridge starting...")
	log.Info().Str("database", cfg.DatabasePath).Msg("Database path")
	log.Info().Str("address", cfg.GRPCAddress).Msg("gRPC address")
	log.Info().Str("address", cfg.MCPAddress).Msg("MCP address")

	// Start parent process monitoring if parent PID is set (subprocess mode)
	if cfg.ParentPID > 0 {
		go monitorParentProcess(cfg.ParentPID)
	}

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

	// Ready channel - closed when gRPC server is listening
	grpcReadyCh := make(chan struct{})

	// Start gRPC server with ready signal
	go func() {
		log.Info().Str("address", cfg.GRPCAddress).Msg("Starting gRPC server")
		if err := grpcServer.StartWithReadySignal(grpcReadyCh); err != nil {
			errCh <- fmt.Errorf("gRPC server error: %w", err)
		}
	}()

	// Start MCP SSE server
	go func() {
		log.Info().Str("address", cfg.MCPAddress).Msg("Starting MCP SSE server")
		if err := mcpServer.Start(); err != nil {
			errCh <- fmt.Errorf("MCP server error: %w", err)
		}
	}()

	// Wait for gRPC server to be ready before signaling
	select {
	case <-grpcReadyCh:
		log.Info().Msg("gRPC server is ready and listening")
	case err := <-errCh:
		log.Fatal().Err(err).Msg("Server failed to start")
	case <-time.After(10 * time.Second):
		log.Fatal().Msg("Timeout waiting for gRPC server to start")
	}

	// Print ready message for subprocess coordination
	// This is printed AFTER the gRPC server is actually listening
	// NOTE: This must remain as plain text (not JSON) for Swift to detect readiness
	fmt.Println("ready")

	// Auto-connect if device is already registered
	if device.ID != nil {
		log.Info().Msg("Device registered, attempting auto-connect...")
		go func() {
			if err := waSvc.Connect(context.Background()); err != nil {
				log.Error().Err(err).Msg("Auto-connect failed")
			} else {
				log.Info().Msg("Auto-connected to WhatsApp")
			}
		}()
	} else {
		log.Info().Msg("No device registered. Use gRPC GetPairingQR to pair a device.")
	}

	// Wait for shutdown signal
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	select {
	case err := <-errCh:
		log.Error().Err(err).Msg("Server error")
	case sig := <-sigCh:
		log.Info().Str("signal", sig.String()).Msg("Received signal, shutting down...")
	}

	// Graceful shutdown
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	log.Info().Msg("Disconnecting WhatsApp...")
	waSvc.Disconnect()

	log.Info().Msg("Stopping gRPC server...")
	grpcServer.Stop()

	log.Info().Msg("Stopping MCP server...")
	if err := mcpServer.Stop(shutdownCtx); err != nil {
		log.Error().Err(err).Msg("MCP server stop error")
	}

	log.Info().Msg("Shutdown complete")
}

func runInteractiveMode(ctx context.Context, waSvc *service.WhatsAppService, msgSvc *service.MessageService, device *store.Device) {
	log := logger.Module("cli")

	// Auto-connect if device is already registered
	if device.ID != nil {
		if err := waSvc.Connect(ctx); err != nil {
			log.Error().Err(err).Msg("Auto-connect failed")
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
		log.Error().Err(err).Msg("CLI error")
	}

	// Cleanup
	waSvc.Disconnect()
}

func runHeadlessMode(ctx context.Context, waSvc *service.WhatsAppService, msgSvc *service.MessageService, device *store.Device) {
	log := logger.Module("cli")

	// Auto-connect if device is already registered
	if device.ID != nil {
		if err := waSvc.Connect(ctx); err != nil {
			// Will report via JSON response
			_ = err
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
		log.Error().Err(err).Msg("CLI error")
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

func initDeviceStore(ctx context.Context, dbPath string, waLogger waLog.Logger) (*store.Device, *sqlstore.Container, error) {
	// Use a separate database file for whatsmeow to avoid schema conflicts
	waDBPath := dbPath[:len(dbPath)-3] + "_wa.db"

	container, err := sqlstore.New(ctx, "sqlite3", "file:"+waDBPath+"?_foreign_keys=on", waLogger)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create sqlstore container: %w", err)
	}

	device, err := container.GetFirstDevice(ctx)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get device: %w", err)
	}

	return device, container, nil
}

// monitorParentProcess checks if the parent process is still alive and exits if it dies.
// This ensures the bridge subprocess doesn't become orphaned when Homie.app crashes or is force-quit.
func monitorParentProcess(parentPID int) {
	log := logger.Module("monitor")
	log.Info().Int("pid", parentPID).Msg("Monitoring parent process")
	for {
		time.Sleep(1 * time.Second)
		process, err := os.FindProcess(parentPID)
		if err != nil {
			log.Info().Int("pid", parentPID).Msg("Parent process not found, exiting...")
			os.Exit(0)
		}
		// On Unix, FindProcess always succeeds, so send signal 0 to check if process exists
		if err := process.Signal(syscall.Signal(0)); err != nil {
			log.Info().Int("pid", parentPID).Err(err).Msg("Parent process gone, exiting...")
			os.Exit(0)
		}
	}
}
