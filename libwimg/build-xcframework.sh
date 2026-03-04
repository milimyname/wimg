#!/bin/bash
set -euo pipefail

# Build libwimg for iOS targets and create XCFramework
# Usage: ./build-xcframework.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build-ios"
INCLUDE_DIR="$SCRIPT_DIR/include"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"/{ios,sim}

echo "=== Building for aarch64-ios ==="
cd "$SCRIPT_DIR"
zig build -Dtarget=aarch64-ios --release=small
cp zig-out/lib/libwimg.a "$BUILD_DIR/ios/libwimg.a"

echo "=== Building for aarch64-ios-simulator ==="
zig build -Dtarget=aarch64-ios-simulator --release=small
cp zig-out/lib/libwimg.a "$BUILD_DIR/sim/libwimg.a"

echo "=== Creating XCFramework ==="
rm -rf "$BUILD_DIR/libwimg.xcframework"
xcodebuild -create-xcframework \
  -library "$BUILD_DIR/ios/libwimg.a" -headers "$INCLUDE_DIR" \
  -library "$BUILD_DIR/sim/libwimg.a" -headers "$INCLUDE_DIR" \
  -output "$BUILD_DIR/libwimg.xcframework"

echo "=== Done ==="
echo "XCFramework at: $BUILD_DIR/libwimg.xcframework"

# Copy to wimg-ios if it exists
IOS_FRAMEWORKS="$SCRIPT_DIR/../wimg-ios/Frameworks"
if [ -d "$SCRIPT_DIR/../wimg-ios" ]; then
  mkdir -p "$IOS_FRAMEWORKS"
  rm -rf "$IOS_FRAMEWORKS/libwimg.xcframework"
  cp -R "$BUILD_DIR/libwimg.xcframework" "$IOS_FRAMEWORKS/"
  echo "Copied to $IOS_FRAMEWORKS/libwimg.xcframework"
fi
