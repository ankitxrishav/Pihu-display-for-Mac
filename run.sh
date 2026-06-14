#!/bin/bash
set -e

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Pihu Display Orchestrator ===${NC}"

# Check for connected ADB devices
echo -e "\n${YELLOW}[1/5] Checking connected Android devices...${NC}"
DEVICE_COUNT=$(/opt/homebrew/bin/adb devices | grep -v "List" | grep "device" | wc -l | xargs)

if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo -e "${RED}Error: No Android devices found connected via USB.${NC}"
    echo -e "Please connect your Android device, enable USB Debugging, and authorize this Mac."
    exit 1
fi
echo -e "${GREEN}Found $DEVICE_COUNT Android device(s) connected.${NC}"

# Build macOS Host App
echo -e "\n${YELLOW}[2/5] Compiling macOS Host App...${NC}"
(cd mac-host && swift build)
echo -e "${GREEN}macOS Host App compiled successfully!${NC}"

# Build Android Client App
echo -e "\n${YELLOW}[3/5] Building Android Client APK...${NC}"
(cd android-client && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug)
echo -e "${GREEN}Android Client APK built successfully!${NC}"

# Forward ADB Port
echo -e "\n${YELLOW}[4/5] Setting up USB port forwarding (adb forward)...${NC}"
/opt/homebrew/bin/adb forward tcp:27183 tcp:27183
echo -e "${GREEN}Port 27183 successfully forwarded over USB!${NC}"

# Install and Launch Android Client
echo -e "\n${YELLOW}[5/5] Installing & launching Android Client app...${NC}"
/opt/homebrew/bin/adb install -r android-client/app/build/outputs/apk/debug/app-debug.apk
/opt/homebrew/bin/adb shell am start -n com.pihu.display/.MainActivity
echo -e "${GREEN}Android Client app launched on device!${NC}"

# Launch macOS Host App
echo -e "\n${YELLOW}=== Starting macOS Host stream... ===${NC}"
echo -e "${YELLOW}Note: If this is your first time, macOS may prompt you for Screen Recording permissions.${NC}"
echo -e "${YELLOW}Press Ctrl+C to terminate.${NC}\n"

exec mac-host/.build/debug/pihu-display-host
