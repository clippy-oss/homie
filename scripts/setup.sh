#!/bin/bash
set -e

HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"

echo "=== Homie Development Setup ==="

# Check Homebrew
if ! command -v brew &> /dev/null; then
    echo "error: Homebrew not installed. Install from https://brew.sh"
    exit 1
fi

# Install Homebrew packages
echo "Installing Homebrew packages..."
brew install protobuf swift-protobuf protoc-gen-grpc-swift go

# Install Go protobuf plugins
echo "Installing Go protobuf plugins..."
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

# Verify installations
echo "Verifying installations..."
GOBIN="${GOBIN:-$(go env GOPATH)/bin}"

MISSING=""
[ ! -f "$HOMEBREW_PREFIX/bin/protoc" ] && MISSING="$MISSING protoc"
[ ! -f "$HOMEBREW_PREFIX/bin/protoc-gen-swift" ] && MISSING="$MISSING protoc-gen-swift"
[ ! -f "$HOMEBREW_PREFIX/opt/protoc-gen-grpc-swift/bin/protoc-gen-grpc-swift-2" ] && MISSING="$MISSING protoc-gen-grpc-swift"
[ ! -f "$HOMEBREW_PREFIX/bin/go" ] && MISSING="$MISSING go"
[ ! -f "$GOBIN/protoc-gen-go" ] && MISSING="$MISSING protoc-gen-go"
[ ! -f "$GOBIN/protoc-gen-go-grpc" ] && MISSING="$MISSING protoc-gen-go-grpc"

if [ -n "$MISSING" ]; then
    echo "error: Missing:$MISSING"
    exit 1
fi

# Generate Go proto files
echo "Generating Go proto files..."
cd "$(dirname "$0")/../whatsapp-bridge"
make proto

echo ""
echo "=== Setup complete ==="
echo "Add to your shell profile: export PATH=\"\$PATH:$GOBIN\""
