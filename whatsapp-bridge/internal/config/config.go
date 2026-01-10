package config

import (
	"flag"
	"os"
	"path/filepath"
	"strconv"
)

type Config struct {
	Mode         string
	DatabasePath string
	MediaPath    string
	GRPCAddress  string
	MCPAddress   string
	ParentPID    int
	LogLevel     string
}

func Load() (*Config, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}
	dataDir := filepath.Join(homeDir, ".whatsapp-bridge")

	cfg := &Config{}

	flag.StringVar(&cfg.Mode, "mode", "server", "Run mode: server, interactive, or headless")
	flag.StringVar(&cfg.DatabasePath, "db", getEnv("WA_DATABASE_PATH", filepath.Join(dataDir, "whatsapp.db")), "Database file path")
	flag.StringVar(&cfg.MediaPath, "media", getEnv("WA_MEDIA_PATH", filepath.Join(dataDir, "media")), "Media download path")
	flag.StringVar(&cfg.GRPCAddress, "grpc-port", getEnv("WA_GRPC_ADDRESS", "127.0.0.1:50051"), "gRPC server address")
	flag.StringVar(&cfg.MCPAddress, "mcp-port", getEnv("WA_MCP_ADDRESS", "127.0.0.1:8080"), "MCP SSE server address")
	flag.StringVar(&cfg.LogLevel, "log-level", getEnv("WA_LOG_LEVEL", "info"), "Log level: debug, info, warn, error")

	flag.Parse()

	// Load parent PID from environment (set by Homie.app when spawning subprocess)
	cfg.ParentPID = getEnvInt("WA_PARENT_PID", 0)

	// Ensure directories exist
	if err := os.MkdirAll(filepath.Dir(cfg.DatabasePath), 0755); err != nil {
		return nil, err
	}
	if err := os.MkdirAll(cfg.MediaPath, 0755); err != nil {
		return nil, err
	}

	return cfg, nil
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
	}
	return defaultValue
}
