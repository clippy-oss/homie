#!/bin/bash
# Xcode Build Phase: Add as first "Run Script" phase
# Check dependencies without installing - fails fast with helpful message

HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
GOBIN="${GOBIN:-$HOME/go/bin}"

MISSING=""

[ ! -f "$HOMEBREW_PREFIX/bin/protoc" ] && MISSING="$MISSING protobuf"
[ ! -f "$HOMEBREW_PREFIX/bin/protoc-gen-swift" ] && MISSING="$MISSING swift-protobuf"
[ ! -f "$HOMEBREW_PREFIX/opt/protoc-gen-grpc-swift/bin/protoc-gen-grpc-swift-2" ] && MISSING="$MISSING protoc-gen-grpc-swift"
[ ! -f "$HOMEBREW_PREFIX/bin/go" ] && MISSING="$MISSING go"
[ ! -f "$GOBIN/protoc-gen-go" ] && MISSING="$MISSING protoc-gen-go"
[ ! -f "$GOBIN/protoc-gen-go-grpc" ] && MISSING="$MISSING protoc-gen-go-grpc"

if [ -n "$MISSING" ]; then
    echo "error: Missing dependencies:$MISSING"
    echo "error: Run ./scripts/setup.sh to install all dependencies"
    exit 1
fi
