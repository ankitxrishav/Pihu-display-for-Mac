#!/bin/bash
set -e

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Pihu Display Orchestrator ===${NC}"

# Parse Command Line Arguments
MODE="auto"
REBUILD_ANDROID=false
HOST=""
BITRATE=""
PAIR=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --mode) MODE="$2"; shift ;;
        --rebuild-android) REBUILD_ANDROID=true ;;
        --host) HOST="$2"; shift ;;
        --bitrate) BITRATE="$2"; shift ;;
        --pair) PAIR="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# 1. Setup ADB Port Forwarding if USB or Auto Mode
if [ "$MODE" = "usb" ]; then
    echo -e "\n${YELLOW}Checking connected Android devices...${NC}"
    DEVICE_COUNT=$(/opt/homebrew/bin/adb devices | grep -v "List" | grep "device" | wc -l | xargs)
    if [ "$DEVICE_COUNT" -eq 0 ]; then
        echo -e "${RED}Error: No Android devices found connected via USB.${NC}"
        echo -e "Please connect your Android device, enable USB Debugging, and authorize this Mac.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Found $DEVICE_COUNT Android device(s) connected.${NC}"
    /opt/homebrew/bin/adb forward tcp:27183 tcp:27183
    echo -e "${GREEN}Port 27183 successfully forwarded over USB!${NC}"
elif [ "$MODE" = "auto" ]; then
    DEVICE_COUNT=$(/opt/homebrew/bin/adb devices | grep -v "List" | grep "device" | wc -l | xargs 2>/dev/null || echo "0")
    if [ "$DEVICE_COUNT" -gt 0 ]; then
        echo -e "${GREEN}Found connected ADB USB device. Setting up port forwarding...${NC}"
        /opt/homebrew/bin/adb forward tcp:27183 tcp:27183
        echo -e "${GREEN}Port 27183 successfully forwarded over USB!${NC}"
    else
        echo -e "${YELLOW}No USB devices detected. Will attempt auto-discovery over local network (Wi-Fi).${NC}"
    fi
fi

# 2. Rebuild and Reinstall Android Client App if requested
if [ "$REBUILD_ANDROID" = true ]; then
    echo -e "\n${YELLOW}Building Android Client APK...${NC}"
    (cd android-client && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug)
    echo -e "${GREEN}Android Client APK built successfully!${NC}"
    
    DEVICE_COUNT=$(/opt/homebrew/bin/adb devices | grep -v "List" | grep "device" | wc -l | xargs 2>/dev/null || echo "0")
    if [ "$DEVICE_COUNT" -gt 0 ]; then
        echo -e "\n${YELLOW}Installing & launching Android Client app...${NC}"
        /opt/homebrew/bin/adb install -r android-client/app/build/outputs/apk/debug/app-debug.apk
        /opt/homebrew/bin/adb shell am start -n com.pihu.display/.MainActivity
        echo -e "${GREEN}Android Client app launched on device!${NC}"
        sleep 2
    else
        echo -e "${RED}Error: --rebuild-android requested but no Android device is connected via USB to install the APK.${NC}"
        exit 1
    fi
fi

# 3. Build macOS Host App
echo -e "\n${YELLOW}Compiling macOS Host App...${NC}"
(cd mac-host && swift build)
echo -e "${GREEN}macOS Host App compiled successfully!${NC}"

# 4. Build Arguments for Host App
HOST_ARGS=()
HOST_ARGS+=( "--mode" "$MODE" )
if [ -n "$HOST" ]; then
    HOST_ARGS+=( "--host" "$HOST" )
fi
if [ -n "$BITRATE" ]; then
    HOST_ARGS+=( "--bitrate" "$BITRATE" )
fi
if [ -n "$PAIR" ]; then
    HOST_ARGS+=( "--pair" "$PAIR" )
fi

# 5. Launch macOS Host App
echo -e "\n${YELLOW}=== Starting macOS Host stream... ===${NC}"
echo -e "${YELLOW}Note: If this is your first time, macOS may prompt you for Screen Recording permissions.${NC}"
echo -e "${YELLOW}Press Ctrl+C to terminate.${NC}\n"

exec mac-host/.build/debug/pihu-display-host "${HOST_ARGS[@]}"
