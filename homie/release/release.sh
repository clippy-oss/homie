#!/bin/bash
# release.sh (macOS direct distribution via DMG)
# bash 3.2 compatible (no mapfile)

set -euo pipefail

SCHEME="homie"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PROJECT_FILE="$PROJECT_DIR/homie.xcodeproj"
ENTITLEMENTS="$PROJECT_DIR/homie/homie.entitlements"

BUILD_DIR="$PROJECT_DIR/build"
OUTPUT_DIR="$PROJECT_DIR/.builds"

log()  { echo "[INFO] $*" >&2; }
ok()   { echo "[OK]   $*" >&2; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERR]  $*" >&2; }
die()  { err "$*"; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

# Load .env
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

# Config from env or defaults
APP_PRODUCT_NAME="${APP_PRODUCT_NAME:-homie}"   # built product: homie.app
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-Homie}"   # staged app + dmg naming

SIGN_IDENTITY="${SIGN_IDENTITY:-${HOMIE_SIGNING_IDENTITY:-}}"
NOTARY_PROFILE="${NOTARY_PROFILE:-${HOMIE_NOTARY_PROFILE:-homie-notary}}"

VERSION="${VERSION:-${HOMIE_VERSION:-}}"
BUILD_NUMBER="${BUILD_NUMBER:-${HOMIE_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}}"

SKIP_BUILD=false
SKIP_ARCHIVE=false
SKIP_NOTARIZE=false
CLEAN_BUILD=false

# Args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2;;
    --build-number) BUILD_NUMBER="$2"; shift 2;;
    --skip-build) SKIP_BUILD=true; shift;;
    --skip-archive) SKIP_ARCHIVE=true; shift;;
    --skip-notarize) SKIP_NOTARIZE=true; shift;;
    --clean) CLEAN_BUILD=true; shift;;
    --help)
      cat <<EOF
Usage: ./release.sh [--version X] [--build-number N] [--clean] [--skip-build] [--skip-archive] [--skip-notarize]

Options:
  --skip-build     Skip entire build (archive + sign)
  --skip-archive   Skip archive, just sign existing archive and create DMG
  --skip-notarize  Skip notarization

Env (.env supported):
  APP_PRODUCT_NAME=homie
  APP_DISPLAY_NAME=Homie
  SIGN_IDENTITY='Developer ID Application: Your Name (YOUR_TEAM_ID)'
  NOTARY_PROFILE=your-notary-profile
EOF
      exit 0
      ;;
    *) die "Unknown option: $1";;
  esac
done

# Validate
[[ -d "$PROJECT_FILE" ]] || die "Xcode project not found: $PROJECT_FILE"
[[ -f "$ENTITLEMENTS" ]] || die "Entitlements not found: $ENTITLEMENTS"
[[ -n "$SIGN_IDENTITY" ]] || die "SIGN_IDENTITY missing. Put it in .env or export it."

require_cmd xcodebuild
require_cmd codesign
require_cmd spctl
require_cmd create-dmg
require_cmd hdiutil
require_cmd xcrun
require_cmd file
require_cmd awk
require_cmd sort
require_cmd cut
require_cmd find
require_cmd ditto
require_cmd wc

read_marketing_version_from_build_settings() {
  xcodebuild -showBuildSettings \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration Release 2>/dev/null \
  | awk -F' = ' '/MARKETING_VERSION/ {print $2; exit}'
}

find_built_app() {
  local app="$BUILD_DIR/Export/${APP_PRODUCT_NAME}.app"
  [[ -d "$app" ]] || die "Built app not found at expected path: $app"
  echo "$app"
}

is_macho() {
  file "$1" 2>/dev/null | grep -q "Mach-O"
}

verify_app() {
  local app="$1"
  log "Verifying app (codesign --deep --strict)..."
  codesign --verify --deep --strict --verbose=2 "$app"

  log "Assessing app (spctl execute)..."
  spctl --assess --type execute --verbose=4 "$app" || true

  log "Authority:"
  codesign -dv --verbose=4 "$app" 2>&1 | egrep "(Authority=|TeamIdentifier=|Identifier=)" || true
  ok "App verification done"
}

create_dmg() {
  local app="$1"
  local version="$2"
  local sign_identity="$3"
  local notary_profile="$4"
  local skip_notarize="$5"
  local app_name
  app_name="$(basename "$app")"
  local dmg="$OUTPUT_DIR/${APP_PRODUCT_NAME}-v${version}.dmg"

  mkdir -p "$OUTPUT_DIR"
  rm -f "$dmg"

  log "Creating DMG..."

  # Build create-dmg command with optional signing and notarization
  local cmd=(
    create-dmg
    --volname "${APP_PRODUCT_NAME} Installer"
    --window-pos 200 120
    --window-size 600 400
    --icon-size 100
    --icon "homie.app" 150 190
    --hide-extension "homie.app"
    --app-drop-link 450 190
    --codesign "$sign_identity"
  )

  if [[ "$skip_notarize" == "false" ]]; then
    cmd+=(--notarize "$notary_profile")
    log "DMG will be signed and notarized using create-dmg"
  else
    log "DMG will be signed only (notarization skipped)"
  fi

  cmd+=("$dmg" "$app")

  # Execute create-dmg
  "${cmd[@]}"

  [[ -f "$dmg" ]] || die "DMG not created at: $dmg"
  echo "$dmg"
}


# Note: sign_dmg and notarize_and_staple_dmg removed - create-dmg handles these via --codesign and --notarize

verify_dmg_contents() {
  local dmg="$1"
  local mount_dir="/tmp/dmg_verify_$$"
  mkdir -p "$mount_dir"

  log "Mounting DMG..."
  hdiutil attach "$dmg" -nobrowse -mountpoint "$mount_dir" >/dev/null

  local app_in_dmg
  app_in_dmg="$(find "$mount_dir" -maxdepth 2 -name "*.app" -type d -print -quit)"
  [[ -n "$app_in_dmg" ]] || {
    hdiutil detach "$mount_dir" >/dev/null || true
    rmdir "$mount_dir" >/dev/null 2>&1 || true
    die "No .app found inside DMG"
  }

  log "Verifying app inside DMG..."
  codesign --verify --deep --strict --verbose=2 "$app_in_dmg"
  spctl --assess --type execute --verbose=4 "$app_in_dmg" || true
  codesign -dv --verbose=4 "$app_in_dmg" 2>&1 | egrep "(Authority=|TeamIdentifier=)" || true

  log "Unmounting DMG..."
  hdiutil detach "$mount_dir" >/dev/null || true
  rmdir "$mount_dir" >/dev/null 2>&1 || true

  ok "DMG contents verified"
}

do_archive() {
  if [[ "$CLEAN_BUILD" == "true" ]]; then
    log "Cleaning build dir..."
    rm -rf "$BUILD_DIR"
  fi
  mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

  log "Resolving SPM dependencies..."
  xcodebuild -resolvePackageDependencies -project "$PROJECT_FILE" -scheme "$SCHEME" >/dev/null

  local archive_path="$BUILD_DIR/${SCHEME}.xcarchive"

  log "Archiving Release..."
  local archive_args=(
    -project "$PROJECT_FILE"
    -scheme "$SCHEME"
    -configuration Release
    -archivePath "$archive_path"
    -destination "generic/platform=macOS"
    PRODUCT_BUNDLE_IDENTIFIER=com.homie.app
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
  )

  if [[ -n "$VERSION" ]]; then
    archive_args+=(MARKETING_VERSION="$VERSION")
  fi

  xcodebuild archive "${archive_args[@]}"

  ok "Archive complete"
}

do_sign() {
  local archive_path="$BUILD_DIR/${SCHEME}.xcarchive"
  local export_path="$BUILD_DIR/Export"

  # Copy app from archive to export directory
  log "Extracting app from archive..."
  mkdir -p "$export_path"
  rm -rf "$export_path/${APP_PRODUCT_NAME}.app"
  local archived_app="$archive_path/Products/Applications/${APP_PRODUCT_NAME}.app"
  [[ -d "$archived_app" ]] || die "App not found in archive: $archived_app"
  cp -R "$archived_app" "$export_path/"

  # Sign the app with Developer ID
  log "Signing with Developer ID..."
  local app="$export_path/${APP_PRODUCT_NAME}.app"

  # Sign nested components first (frameworks, dylibs, helpers)
  while IFS= read -r fw; do
    [[ -n "$fw" ]] || continue
    log "  Signing framework: $(basename "$fw")"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$fw"
  done < <(find "$app/Contents/Frameworks" -name "*.framework" -type d 2>/dev/null)

  while IFS= read -r dylib; do
    [[ -n "$dylib" ]] || continue
    log "  Signing dylib: $(basename "$dylib")"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$dylib"
  done < <(find "$app" -name "*.dylib" -type f 2>/dev/null)

  while IFS= read -r bundle; do
    [[ -n "$bundle" ]] || continue
    log "  Signing bundle: $(basename "$bundle")"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$bundle"
  done < <(find "$app" -name "*.bundle" -type d 2>/dev/null)

  # Sign helper executables in Frameworks
  while IFS= read -r helper; do
    [[ -n "$helper" ]] || continue
    if file "$helper" 2>/dev/null | grep -q "Mach-O"; then
      log "  Signing helper: $(basename "$helper")"
      codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$helper"
    fi
  done < <(find "$app/Contents/Frameworks" -type f -perm +111 2>/dev/null)

  # Sign XPC services
  while IFS= read -r xpc; do
    [[ -n "$xpc" ]] || continue
    log "  Signing XPC: $(basename "$xpc")"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$xpc"
  done < <(find "$app" -name "*.xpc" -type d 2>/dev/null)

  # Sign main app with entitlements
  log "  Signing main app..."
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$app"

  ok "Signing complete"
}

# -----------------------------
# Main
# -----------------------------
echo ""
log "============================================"
log "Release: $APP_DISPLAY_NAME"
log "============================================"
echo ""

if [[ "$SKIP_BUILD" == "false" ]]; then
  if [[ "$SKIP_ARCHIVE" == "false" ]]; then
    do_archive
  else
    log "Skipping archive (using existing)"
  fi
  do_sign
else
  log "Skipping build entirely"
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(read_marketing_version_from_build_settings)"
  [[ -n "$VERSION" ]] || die "Could not read MARKETING_VERSION. Fix xcconfig or pass --version."
  log "Using MARKETING_VERSION from build settings: $VERSION"
else
  log "Using version from CLI/env: $VERSION"
fi

BUILT_APP="$(find_built_app)"
log "Built app: $BUILT_APP"

# Xcode already signed the app during build, just verify it
verify_app "$BUILT_APP"

# Create DMG with signing and optional notarization (handled by create-dmg)
DMG_PATH="$(create_dmg "$BUILT_APP" "$VERSION" "$SIGN_IDENTITY" "$NOTARY_PROFILE" "$SKIP_NOTARIZE")"

if [[ "$SKIP_NOTARIZE" == "true" ]]; then
  warn "Notarization skipped. Users will likely need right click then Open."
fi

verify_dmg_contents "$DMG_PATH"

echo ""
ok "Done"
log "Artifacts:"
log "  App: $BUILT_APP"
log "  DMG: $DMG_PATH"
echo ""
