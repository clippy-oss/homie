package config

import (
	"flag"
	"os"
	"path/filepath"
)

type Config struct {
	Mode         string
	DatabasePath string
	MediaPath    string
	GRPCAddress  string
	MCPAddress   string
}

func Load() *Config {
	homeDir, _ := os.UserHomeDir()
	dataDir := filepath.Join(homeDir, ".whatsapp-bridge")

	cfg := &Config{}

	flag.StringVar(&cfg.Mode, "mode", "server", "Run mode: server, interactive, or headless")
	flag.StringVar(&cfg.DatabasePath, "db", getEnv("WA_DATABASE_PATH", filepath.Join(dataDir, "whatsapp.db")), "Database file path")
	flag.StringVar(&cfg.MediaPath, "media", getEnv("WA_MEDIA_PATH", filepath.Join(dataDir, "media")), "Media download path")
	flag.StringVar(&cfg.GRPCAddress, "grpc-port", getEnv("WA_GRPC_ADDRESS", "127.0.0.1:50051"), "gRPC server address")
	flag.StringVar(&cfg.MCPAddress, "mcp-port", getEnv("WA_MCP_ADDRESS", "127.0.0.1:8080"), "MCP SSE server address")

	flag.Parse()

	// Ensure directories exist
	os.MkdirAll(filepath.Dir(cfg.DatabasePath), 0755)
	os.MkdirAll(cfg.MediaPath, 0755)

	return cfg
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
