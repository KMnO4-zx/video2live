#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

SWIFT_BIN="${SWIFT_BIN:-swift}"
if ! xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1 && [[ -x /Library/Developer/CommandLineTools/usr/bin/swift ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
  SWIFT_BIN=/Library/Developer/CommandLineTools/usr/bin/swift
fi

"$SWIFT_BIN" build -c release

APP_DIR=".build/release/Video2Live.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp .build/release/Video2Live "$MACOS_DIR/Video2Live"
cp Info.plist "$CONTENTS_DIR/Info.plist"
codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
