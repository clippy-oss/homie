.PHONY: all build build-bridge build-app run clean help
.PHONY: build-debug build-release install-bridge
.PHONY: bridge-run bridge-interactive bridge-headless
.PHONY: kill-bridge ps

# Directories
PROJECT_ROOT := $(shell pwd)
HOMIE_DIR := $(PROJECT_ROOT)/homie
BRIDGE_DIR := $(PROJECT_ROOT)/whatsapp-bridge

# Xcode settings
SCHEME := homie
CONFIGURATION ?= Debug
BUILD_DIR := $(HOMIE_DIR)/build
DERIVED_DATA := $(BUILD_DIR)/DerivedData
APP_NAME := homie.app

# WhatsApp bridge settings
BRIDGE_BINARY := whatsapp-bridge
BRIDGE_BIN_DIR := $(BRIDGE_DIR)/bin

# Default target
all: build

# ============================================================================
# Main Build Targets
# ============================================================================

## build: Build both whatsapp-bridge and Homie.app (Debug)
build: build-bridge build-app

## build-debug: Build everything in Debug configuration
build-debug: CONFIGURATION=Debug
build-debug: build

## build-release: Build everything in Release configuration
build-release: CONFIGURATION=Release
build-release: build

# ============================================================================
# WhatsApp Bridge Targets
# ============================================================================

## build-bridge: Build the whatsapp-bridge Go binary
build-bridge:
	@echo "Building whatsapp-bridge..."
	@cd $(BRIDGE_DIR) && make build

## install-bridge: Build and copy bridge binary to app resources
install-bridge: build-bridge
	@echo "Installing whatsapp-bridge to app bundle..."
	@mkdir -p "$(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME)/Contents/Resources"
	@cp "$(BRIDGE_BIN_DIR)/$(BRIDGE_BINARY)" "$(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME)/Contents/Resources/"
	@echo "Bridge installed successfully"

## bridge-run: Run whatsapp-bridge in server mode (standalone)
bridge-run:
	@cd $(BRIDGE_DIR) && ./bin/$(BRIDGE_BINARY) -mode server

## bridge-interactive: Run whatsapp-bridge in interactive CLI mode
bridge-interactive:
	@cd $(BRIDGE_DIR) && ./bin/$(BRIDGE_BINARY) -mode interactive

## bridge-headless: Run whatsapp-bridge in headless mode
bridge-headless:
	@cd $(BRIDGE_DIR) && ./bin/$(BRIDGE_BINARY) -mode headless

# ============================================================================
# Homie.app Targets
# ============================================================================

## build-app: Build Homie.app using xcodebuild
build-app:
	@echo "Building Homie.app ($(CONFIGURATION))..."
	@xcodebuild -project "$(HOMIE_DIR)/homie.xcodeproj" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		build \
		| xcbeautify || xcodebuild -project "$(HOMIE_DIR)/homie.xcodeproj" \
			-scheme "$(SCHEME)" \
			-configuration "$(CONFIGURATION)" \
			-derivedDataPath "$(DERIVED_DATA)" \
			build

## run: Build and run Homie.app
run: build
	@echo "Running Homie.app..."
	@open "$(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME)"

## run-app: Run Homie.app without rebuilding (must be built first)
run-app:
	@echo "Running Homie.app..."
	@open "$(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME)"

# ============================================================================
# Utility Targets
# ============================================================================

## clean: Clean all build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf "$(BUILD_DIR)"
	@cd $(BRIDGE_DIR) && make clean
	@xcodebuild -project "$(HOMIE_DIR)/homie.xcodeproj" \
		-scheme "$(SCHEME)" \
		clean 2>/dev/null || true
	@echo "Clean complete"

## kill-bridge: Kill any running whatsapp-bridge processes
kill-bridge:
	@echo "Killing whatsapp-bridge processes..."
	@pkill -f whatsapp-bridge 2>/dev/null || echo "No whatsapp-bridge processes running"

## ps: Show running Homie and whatsapp-bridge processes
ps:
	@echo "=== Homie.app ==="
	@ps aux | grep -i "[h]omie" || echo "Not running"
	@echo ""
	@echo "=== whatsapp-bridge ==="
	@ps aux | grep "[w]hatsapp-bridge" || echo "Not running"

## logs: Tail Homie.app logs (if using os_log)
logs:
	@log stream --predicate 'subsystem CONTAINS "homie"' --level debug

# ============================================================================
# Development Helpers
# ============================================================================

## dev: Build and run in development mode with verbose logging
dev: build
	@echo "Starting Homie.app in development mode..."
	@HOMIE_DEBUG=1 open "$(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME)"

## test: Run tests
test:
	@echo "Running tests..."
	@xcodebuild -project "$(HOMIE_DIR)/homie.xcodeproj" \
		-scheme "$(SCHEME)" \
		-configuration Debug \
		-derivedDataPath "$(DERIVED_DATA)" \
		test \
		| xcbeautify || xcodebuild -project "$(HOMIE_DIR)/homie.xcodeproj" \
			-scheme "$(SCHEME)" \
			-configuration Debug \
			-derivedDataPath "$(DERIVED_DATA)" \
			test

## xcode: Open project in Xcode
xcode:
	@open "$(HOMIE_DIR)/homie.xcodeproj"

# ============================================================================
# Help
# ============================================================================

## help: Show this help message
help:
	@echo "Homie Project Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Main Targets:"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /' | column -t -s ':'
	@echo ""
	@echo "Examples:"
	@echo "  make build          # Build everything (Debug)"
	@echo "  make build-release  # Build everything (Release)"
	@echo "  make run            # Build and run Homie.app"
	@echo "  make bridge-interactive  # Run bridge CLI"
	@echo "  make ps             # Show running processes"
	@echo "  make kill-bridge    # Kill orphaned bridge processes"

.DEFAULT_GOAL := help
