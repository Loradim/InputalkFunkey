#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Inputalk Funkey.app"
BUILT_APP="$PROJECT_DIR/dist/$APP_NAME"
INSTALL_APP="/Applications/$APP_NAME"

cd "$PROJECT_DIR"

UNIVERSAL=false "$SCRIPT_DIR/build-app.sh"

xattr -cr "$BUILT_APP"
codesign --force --deep --sign - "$BUILT_APP"

rm -rf "$INSTALL_APP"
cp -R "$BUILT_APP" "$INSTALL_APP"

echo "Installed $APP_NAME to /Applications"
