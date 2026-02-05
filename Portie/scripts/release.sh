#!/bin/bash
set -e

# Release script for Portie
# Usage: ./scripts/release.sh [path-to-notarized-app]
# Version is automatically read from the app's Info.plist

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"

APP_SOURCE="${1:-$PROJECT_ROOT/Portie.app}"
ZIP_PATH="$PROJECT_ROOT/Portie.zip"

if [ ! -d "$APP_SOURCE" ]; then
    echo "Error: Portie.app not found at $APP_SOURCE"
    echo "Usage: $0 [path-to-notarized-app]"
    exit 1
fi

VERSION="v$(defaults read "$APP_SOURCE/Contents/Info" CFBundleShortVersionString)"
echo "Detected version: $VERSION"

echo "Creating zip from $APP_SOURCE..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_SOURCE" "$ZIP_PATH"

echo "Deleting existing release $VERSION (if any)..."
gh release delete "$VERSION" --yes 2>/dev/null || true

echo "Creating release $VERSION..."
gh release create "$VERSION" "$ZIP_PATH" \
    --title "Portie $VERSION" \
    --notes "Notarized macOS app release"

echo "Done! Release available at:"
gh release view "$VERSION" --json url -q .url
