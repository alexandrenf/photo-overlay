#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 [--zip]"
  echo ""
  echo "Build Overlay.app, ad-hoc sign it, and optionally create a release zip."
}

CREATE_ZIP=false
case "${1:-}" in
  "") ;;
  --zip) CREATE_ZIP=true ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: Overlay can only be packaged on macOS." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
APP_BUNDLE="$DIST_DIR/Overlay.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
ICON_PATH="$CONTENTS_DIR/Resources/AppIcon.icns"
ZIP_PATH="$DIST_DIR/Overlay-macOS.zip"

if [[ -z "$DIST_DIR" || "$DIST_DIR" == "/" ]]; then
  echo "error: refusing to use unsafe DIST_DIR '$DIST_DIR'." >&2
  exit 1
fi

echo "Building Overlay $APP_VERSION (release)…"
cd "$REPO_ROOT"
swift build -c release --product Overlay
BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY_PATH="$BIN_DIR/Overlay"

if [[ ! -x "$BINARY_PATH" ]]; then
  echo "error: release binary not found at $BINARY_PATH" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$CONTENTS_DIR/Resources"
install -m 755 "$BINARY_PATH" "$MACOS_DIR/Overlay"

rm -rf "$ICONSET_DIR"
swift "$REPO_ROOT/scripts/generate_icon.swift" "$ICONSET_DIR"
iconutil --convert icns --output "$ICON_PATH" "$ICONSET_DIR"
rm -rf "$ICONSET_DIR"

plutil -create xml1 "$INFO_PLIST"
plutil -insert CFBundleDevelopmentRegion -string en "$INFO_PLIST"
plutil -insert CFBundleExecutable -string Overlay "$INFO_PLIST"
plutil -insert CFBundleIdentifier -string com.alexandrenf.photo-overlay "$INFO_PLIST"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$INFO_PLIST"
plutil -insert CFBundleName -string Overlay "$INFO_PLIST"
plutil -insert CFBundleDisplayName -string Overlay "$INFO_PLIST"
plutil -insert CFBundleIconFile -string AppIcon "$INFO_PLIST"
plutil -insert CFBundlePackageType -string APPL "$INFO_PLIST"
plutil -insert CFBundleShortVersionString -string "$APP_VERSION" "$INFO_PLIST"
plutil -insert CFBundleVersion -string "$BUILD_NUMBER" "$INFO_PLIST"
plutil -insert LSMinimumSystemVersion -string 14.0 "$INFO_PLIST"
plutil -insert LSUIElement -bool true "$INFO_PLIST"
plutil -insert NSHighResolutionCapable -bool true "$INFO_PLIST"

plutil -lint "$INFO_PLIST"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "Created $APP_BUNDLE"

if [[ "$CREATE_ZIP" == true ]]; then
  rm -f "$ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
  echo "Created $ZIP_PATH"
fi
