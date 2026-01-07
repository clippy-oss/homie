#!/bin/bash

# Generate Sparkle appcast.xml from Supabase app_versions table
# This script fetches the latest version info and generates the appcast feed

set -e

# Load environment variables from .env if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
ENV_FILE="${ENV_FILE:-$PROJECT_ROOT/.env}"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# Required environment variables
SUPABASE_URL="${SUPABASE_URL:-}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
    echo "Error: Missing required environment variables"
    echo "Required: SUPABASE_URL, SUPABASE_ANON_KEY"
    echo "Set them in .env or export them before running this script"
    exit 1
fi

APP_NAME="Homie"
BUNDLE_ID="com.homie.app"
APPCAST_FILE="appcast.xml"
SIGN_UPDATE_BIN="./bin/sign_update"
PRIVATE_KEY="./dsa_priv.pem"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🚀 Generating Sparkle appcast..."

# Check if sign_update binary exists
if [ ! -f "$SIGN_UPDATE_BIN" ]; then
    echo -e "${YELLOW}⚠️  Warning: sign_update binary not found at $SIGN_UPDATE_BIN${NC}"
    echo "   Update archives will not be signed. Install Sparkle tools to enable signing."
    SIGN_ENABLED=false
else
    SIGN_ENABLED=true
    chmod +x "$SIGN_UPDATE_BIN" 2>/dev/null || true
fi

# Check if private key exists
if [ "$SIGN_ENABLED" = true ] && [ ! -f "$PRIVATE_KEY" ]; then
    echo -e "${YELLOW}⚠️  Warning: Private key not found at $PRIVATE_KEY${NC}"
    echo "   Update archives will not be signed. Generate keys first (see SPARKLE_CODE_SIGNING_SETUP.md)"
    SIGN_ENABLED=false
fi

# Fetch latest version from Supabase Edge Function
echo "📡 Fetching latest version from Supabase..."
LATEST_VERSION_JSON=$(curl -s "${SUPABASE_URL}/functions/v1/get-latest-version" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json")

# Check if request was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to fetch version from Supabase${NC}"
    exit 1
fi

# Parse JSON (using basic parsing, assumes jq is not available)
VERSION=$(echo "$LATEST_VERSION_JSON" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
BUILD=$(echo "$LATEST_VERSION_JSON" | grep -o '"build":[0-9]*' | cut -d':' -f2)
ZIP_URL=$(echo "$LATEST_VERSION_JSON" | grep -o '"zip_url":"[^"]*"' | cut -d'"' -f4)
RELEASE_NOTES=$(echo "$LATEST_VERSION_JSON" | grep -o '"release_notes":"[^"]*"' | cut -d'"' -f4 | sed 's/\\n/\n/g')
MIN_OS_VERSION=$(echo "$LATEST_VERSION_JSON" | grep -o '"min_os_version":"[^"]*"' | cut -d'"' -f4 || echo "15.0")
IS_REQUIRED=$(echo "$LATEST_VERSION_JSON" | grep -o '"is_required":[^,}]*' | cut -d':' -f2 | tr -d ' ')

if [ -z "$VERSION" ] || [ -z "$BUILD" ] || [ -z "$ZIP_URL" ]; then
    echo -e "${RED}❌ Failed to parse version information${NC}"
    echo "Response: $LATEST_VERSION_JSON"
    exit 1
fi

echo -e "${GREEN}✅ Found version: $VERSION (build $BUILD)${NC}"

# Get file size and signature
echo "📦 Processing update archive..."

# Download file to get size (or use HEAD request)
FILE_SIZE=$(curl -sI "$ZIP_URL" | grep -i "content-length" | awk '{print $2}' | tr -d '\r\n')
if [ -z "$FILE_SIZE" ]; then
    FILE_SIZE="0"
fi

# Generate signature if signing is enabled
SIGNATURE=""
if [ "$SIGN_ENABLED" = true ]; then
    echo "🔐 Signing update archive..."
    
    # Download file temporarily to sign it
    TEMP_ZIP=$(mktemp)
    curl -s "$ZIP_URL" -o "$TEMP_ZIP"
    
    SIGNATURE_OUTPUT=$("$SIGN_UPDATE_BIN" "$TEMP_ZIP" "$PRIVATE_KEY" 2>&1)
    if [ $? -eq 0 ]; then
        SIGNATURE=$(echo "$SIGNATURE_OUTPUT" | grep -o 'length="[0-9]*">[^<]*' | sed 's/.*">//')
        echo -e "${GREEN}✅ Archive signed successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  Failed to sign archive: $SIGNATURE_OUTPUT${NC}"
    fi
    
    rm -f "$TEMP_ZIP"
fi

# Get public key if available
PUBLIC_KEY=""
if [ -f "./dsa_pub.pem" ]; then
    PUBLIC_KEY=$(cat ./dsa_pub.pem | grep -v "BEGIN\|END" | tr -d '\n')
fi

# Generate appcast.xml
echo "📝 Generating appcast.xml..."

cat > "$APPCAST_FILE" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>${APP_NAME} Changelog</title>
        <link>${SUPABASE_URL}/storage/v1/object/public/app-updates/appcast.xml</link>
        <description>Most recent changes with links to updates.</description>
        <language>en</language>
EOF

# Add public key if available
if [ -n "$PUBLIC_KEY" ]; then
    echo "        <pubKey>${PUBLIC_KEY}</pubKey>" >> "$APPCAST_FILE"
fi

cat >> "$APPCAST_FILE" <<EOF
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>$(date -u +"%a, %d %b %Y %H:%M:%S %z")</pubDate>
            <sparkle:minimumSystemVersion>${MIN_OS_VERSION}</sparkle:minimumSystemVersion>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
EOF

# Add enclosure with signature if available
if [ -n "$SIGNATURE" ]; then
    cat >> "$APPCAST_FILE" <<EOF
            <enclosure url="${ZIP_URL}" 
                       sparkle:version="${BUILD}" 
                       sparkle:shortVersionString="${VERSION}"
                       length="${FILE_SIZE}"
                       type="application/octet-stream"
                       sparkle:edSignature="${SIGNATURE}" />
EOF
else
    cat >> "$APPCAST_FILE" <<EOF
            <enclosure url="${ZIP_URL}" 
                       sparkle:version="${BUILD}" 
                       sparkle:shortVersionString="${VERSION}"
                       length="${FILE_SIZE}"
                       type="application/octet-stream" />
EOF
fi

# Add release notes
if [ -n "$RELEASE_NOTES" ]; then
    # Escape XML special characters
    ESCAPED_NOTES=$(echo "$RELEASE_NOTES" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&apos;/g')
    cat >> "$APPCAST_FILE" <<EOF
            <description><![CDATA[
${ESCAPED_NOTES}
            ]]></description>
EOF
fi

# Add required update flag
if [ "$IS_REQUIRED" = "true" ]; then
    echo "            <sparkle:criticalUpdate sparkle:minimumVersion=\"${BUILD}\" />" >> "$APPCAST_FILE"
fi

cat >> "$APPCAST_FILE" <<EOF
        </item>
    </channel>
</rss>
EOF

echo -e "${GREEN}✅ Appcast generated: $APPCAST_FILE${NC}"
echo ""
echo "📤 Next steps:"
echo "   1. Review $APPCAST_FILE"
echo "   2. Upload to Supabase Storage: app-updates/appcast.xml"
echo "   3. Make sure it's publicly accessible"
echo ""
echo "🔗 Appcast URL will be:"
echo "   ${SUPABASE_URL}/storage/v1/object/public/app-updates/appcast.xml"

