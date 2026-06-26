#!/bin/bash
set -e

# Color definitions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Determine Mac's local IP address
# en0 is typical Wi-Fi on Mac. Fall back to first non-loopback inet if en0 has no IP.
IP_ADDR=$(ipconfig getifaddr en0 2>/dev/null || ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1)

if [ -z "$IP_ADDR" ]; then
    echo -e "\033[0;31mError: Could not determine Mac local IP address. Are you connected to Wi-Fi or Hotspot?\033[0m"
    exit 1
fi

APK_URL="http://${IP_ADDR}:8000/pihu-display.apk"

echo -e "${GREEN}=== Pihu Display APK Server ===${NC}"
echo -e "Connect your phone to the same Wi-Fi/Hotspot network."
echo -e "Download and install the APK on your phone from: ${YELLOW}${APK_URL}${NC}"
echo -e ""

if which qrencode > /dev/null; then
    echo -e "Or scan this QR code to download the APK directly:"
    qrencode -t ansiutf8 "${APK_URL}"
else
    echo -e "${YELLOW}Tip: Install 'qrencode' (brew install qrencode) to generate a QR code directly in the terminal!${NC}"
fi

echo -e "\nStarting HTTP server on port 8000 (Press Ctrl+C to stop)..."
cd "$(dirname "$0")/../dist"
exec python3 -m http.server 8000
