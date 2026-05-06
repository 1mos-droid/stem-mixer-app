#!/bin/bash

# Deep Size Optimization Build Script
# Targets: arm64-v8a only, Splitting per ABI, Minified

echo "Starting scorched-earth clean..."
cd android && ./gradlew clean && cd ..
flutter clean
flutter pub get

echo "Building Lean ARM64 APK..."
flutter build apk --split-per-abi --target-platform android-arm64

echo "Build complete. Check build/app/outputs/flutter-apk/ for the arm64-v8a APK."
