#!/bin/bash
set -e

# Color definitions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Building Android Client APK ===${NC}"

# Navigate to android-client and build
cd "$(dirname "$0")/../android-client"
JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug

# Ensure dist directory exists
mkdir -p ../dist

# Copy APK to dist/
cp app/build/outputs/apk/debug/app-debug.apk ../dist/pihu-display.apk

echo -e "${GREEN}Android Client APK built successfully at dist/pihu-display.apk!${NC}"
