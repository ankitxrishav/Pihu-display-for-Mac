#!/bin/bash
set -e

# Color definitions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Pihu Display Package Automator ===${NC}"

# Navigate to project root
cd "$(dirname "$0")/.."
ROOT_DIR=$(pwd)

# 1. Compile Android Client APK
echo -e "\n${YELLOW}[1/4] Compiling Android Client APK...${NC}"
./scripts/build-apk.sh

# 2. Compile macOS Host App in Release Mode
echo -e "\n${YELLOW}[2/4] Compiling macOS Host App in Release Mode...${NC}"
cd "${ROOT_DIR}/mac-host"
swift build -c release
cd "${ROOT_DIR}"

# 3. Create macOS App Bundle Structure
echo -e "\n${YELLOW}[3/4] Creating App Bundle structure...${NC}"
APP_NAME="Pihu Display"
APP_DIR="${ROOT_DIR}/dist/${APP_NAME}.app"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy Compiled Binary
cp "${ROOT_DIR}/mac-host/.build/release/pihu-display-host" "${APP_DIR}/Contents/MacOS/pihu-display-host"

# Copy Android Client APK to Resources
cp "${ROOT_DIR}/dist/pihu-display.apk" "${APP_DIR}/Contents/Resources/pihu-display.apk"

# Write Info.plist
echo -e "${YELLOW}Writing Info.plist...${NC}"
cat <<EOF > "${APP_DIR}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Pihu Display</string>
    <key>CFBundleExecutable</key>
    <string>pihu-display-host</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.pihu.display</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Pihu Display</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>Pihu Display does not use the camera, but requires video authorization for virtual screen streaming.</string>
</dict>
</plist>
EOF

# 4. Generate AppIcon if it exists, otherwise copy generic/empty placeholder
echo -e "\n${YELLOW}[4/4] Processing AppIcon...${NC}"
ICONSET_DIR="${ROOT_DIR}/dist/AppIcon.iconset"
if [ -f "${ROOT_DIR}/assets/app_icon.png" ]; then
    echo -e "${GREEN}Found custom app icon. Generating AppIcon.icns...${NC}"
    rm -rf "${ICONSET_DIR}"
    mkdir -p "${ICONSET_DIR}"
    
    # Generate the icon sizes required by macOS
    sips -s format png -z 16 16     "${ROOT_DIR}/assets/app_icon.png" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null
    sips -s format png -z 32 32     "${ROOT_DIR}/assets/app_icon.png" --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null
    sips -s format png -z 32 32     "${ROOT_DIR}/assets/app_icon.png" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null
    sips -s format png -z 64 64     "${ROOT_DIR}/assets/app_icon.png" --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null
    sips -s format png -z 128 128   "${ROOT_DIR}/assets/app_icon.png" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null
    sips -s format png -z 256 256   "${ROOT_DIR}/assets/app_icon.png" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null
    sips -s format png -z 256 256   "${ROOT_DIR}/assets/app_icon.png" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null
    sips -s format png -z 512 512   "${ROOT_DIR}/assets/app_icon.png" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null
    sips -s format png -z 512 512   "${ROOT_DIR}/assets/app_icon.png" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null
    sips -s format png -z 1024 1024 "${ROOT_DIR}/assets/app_icon.png" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null
    
    # Compile into icns
    iconutil -c icns "${ICONSET_DIR}" -o "${APP_DIR}/Contents/Resources/AppIcon.icns"
    rm -rf "${ICONSET_DIR}"
    echo -e "${GREEN}AppIcon.icns successfully integrated!${NC}"
else
    echo -e "${YELLOW}No custom app_icon.png found in assets/. Using generic app icon.${NC}"
    # Touch an empty/basic file to prevent crashes, or we will generate one later
    touch "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

echo -e "\n${GREEN}=====================================${NC}"
echo -e "${GREEN}Success! Build complete!${NC}"
echo -e "${GREEN}Application available at: ${YELLOW}${APP_DIR}${NC}"
echo -e "${GREEN}=====================================${NC}"
