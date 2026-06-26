#!/bin/bash
# OISS - Build script for all platforms

set -e

APP_DIR="app"
DIST_DIR="dist"

echo "=== OISS Build Script ==="
echo "Building Flutter applications for multiple platforms..."

mkdir -p "$DIST_DIR"

cd "$APP_DIR" || exit

# Linux
echo "Building for Linux..."
flutter build linux
cp -r build/linux/x64/release/bundle/* "../$DIST_DIR/linux/" || echo "Linux build copy skipped."

# Web
echo "Building for Web..."
flutter build web
cp -r build/web/* "../$DIST_DIR/web/" || echo "Web build copy skipped."

# Android (APK)
echo "Building for Android (APK)..."
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk "../$DIST_DIR/oiss-android.apk" || echo "Android build copy skipped."

# Windows
echo "Building for Windows... (Note: Only works on a Windows host)"
# flutter build windows
# cp -r build/windows/runner/Release/* "../$DIST_DIR/windows/"

# macOS
echo "Building for macOS... (Note: Only works on a macOS host)"
# flutter build macos
# cp -r build/macos/Build/Products/Release/app.app "../$DIST_DIR/macos/"

# iOS
echo "Building for iOS... (Note: Only works on a macOS host with Xcode)"
# flutter build ios --release

echo "Build process completed. Check the '$DIST_DIR' folder."
