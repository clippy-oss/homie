#!/bin/bash

# Upload DMG to Cloudflare R2 using AWS CLI
# Usage: ./upload_to_r2.sh <dmg_file>
# Example: ./upload_to_r2.sh ../. builds/Homie-v0.4.0-alpha.1.dmg

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
ENV_FILE="$PROJECT_ROOT/.env"

# Load environment variables from .env
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

# Validate required environment variables
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$CLOUDFLARE_S3_API" ]; then
    echo "Error: Missing required environment variables"
    echo "Required: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, CLOUDFLARE_S3_API"
    exit 1
fi

# Check for DMG file argument
if [ -z "$1" ]; then
    echo "Usage: $0 <dmg_file>"
    echo "Example: $0 ../.builds/Homie-v0.4.0-alpha.1.dmg"
    exit 1
fi

DMG_FILE="$1"
BUCKET_NAME="homie"

# Resolve relative path
if [[ ! "$DMG_FILE" = /* ]]; then
    DMG_FILE="$SCRIPT_DIR/$DMG_FILE"
fi

if [ ! -f "$DMG_FILE" ]; then
    echo "Error: File not found: $DMG_FILE"
    exit 1
fi

FILENAME=$(basename "$DMG_FILE")
FILE_SIZE=$(du -h "$DMG_FILE" | cut -f1)

echo "Uploading $FILENAME ($FILE_SIZE) to Cloudflare R2..."
echo "Bucket: $BUCKET_NAME"
echo "Endpoint: $CLOUDFLARE_S3_API"

aws s3 cp "$DMG_FILE" "s3://$BUCKET_NAME/$FILENAME" \
    --endpoint-url "$CLOUDFLARE_S3_API"

echo ""
echo "Upload complete!"
# R2_PUBLIC_URL should be set in .env
if [ -n "$R2_PUBLIC_URL" ]; then
    echo "Public URL: $R2_PUBLIC_URL/$FILENAME"
else
    echo "Note: Set R2_PUBLIC_URL in .env to show the public URL"
fi
