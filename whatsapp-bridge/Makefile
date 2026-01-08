.PHONY: all build proto clean test run deps lint

# Go parameters
GOCMD=go
GOBUILD=$(GOCMD) build
GOCLEAN=$(GOCMD) clean
GOTEST=$(GOCMD) test
GOGET=$(GOCMD) get
GOMOD=$(GOCMD) mod

# Binary name
BINARY_NAME=whatsapp-bridge
BINARY_DIR=bin

# Proto parameters
PROTO_DIR=api/proto
PROTO_OUT=pkg/pb

all: proto build

build:
	@echo "Building $(BINARY_NAME)..."
	@mkdir -p $(BINARY_DIR)
	CGO_ENABLED=1 $(GOBUILD) -o $(BINARY_DIR)/$(BINARY_NAME) ./cmd/whatsapp-bridge

proto:
	@echo "Generating protobuf code..."
	@mkdir -p $(PROTO_OUT)
	protoc --go_out=$(PROTO_OUT) --go_opt=paths=source_relative \
		--go-grpc_out=$(PROTO_OUT) --go-grpc_opt=paths=source_relative \
		-I$(PROTO_DIR) \
		$(PROTO_DIR)/whatsapp.proto

clean:
	@echo "Cleaning..."
	$(GOCLEAN)
	rm -rf $(BINARY_DIR)
	rm -rf $(PROTO_OUT)/*.go

test:
	@echo "Running tests..."
	$(GOTEST) -v ./...

run: build
	./$(BINARY_DIR)/$(BINARY_NAME)

deps:
	@echo "Installing dependencies..."
	$(GOGET) google.golang.org/protobuf/cmd/protoc-gen-go@latest
	$(GOGET) google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
	$(GOMOD) tidy

tidy:
	$(GOMOD) tidy

lint:
	@echo "Running linter..."
	golangci-lint run ./...

# Development helpers
dev: build
	WA_GRPC_ADDRESS=127.0.0.1:50051 WA_MCP_ADDRESS=127.0.0.1:8080 ./$(BINARY_DIR)/$(BINARY_NAME)

# Build for macOS arm64 (for bundling with Swift app)
build-macos-arm64:
	@echo "Building for macOS arm64..."
	@mkdir -p $(BINARY_DIR)
	CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 $(GOBUILD) -o $(BINARY_DIR)/$(BINARY_NAME)-darwin-arm64 ./cmd/whatsapp-bridge

# Build for macOS amd64
build-macos-amd64:
	@echo "Building for macOS amd64..."
	@mkdir -p $(BINARY_DIR)
	CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 $(GOBUILD) -o $(BINARY_DIR)/$(BINARY_NAME)-darwin-amd64 ./cmd/whatsapp-bridge

# Build universal binary for macOS
build-macos-universal: build-macos-arm64 build-macos-amd64
	@echo "Creating universal binary..."
	lipo -create -output $(BINARY_DIR)/$(BINARY_NAME)-darwin-universal \
		$(BINARY_DIR)/$(BINARY_NAME)-darwin-arm64 \
		$(BINARY_DIR)/$(BINARY_NAME)-darwin-amd64

.DEFAULT_GOAL := all
