# Pihu Display v2.0 (Mac & Android)

<a href="https://www.producthunt.com/products/pihu-display?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-pihu-display" target="_blank" rel="noopener noreferrer"><img alt="Pihu Display - Turn your Android into a wired second monitor for macOS. | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1172355&amp;theme=light&amp;t=1781789732295"></a>

Pihu Display is a high-performance system tool that lets you use any Android device as a secondary monitor for your Mac over USB or Wi-Fi. It achieves sub-40ms latency by using hardware video encoding/decoding, virtual display buffers, and high-throughput TCP streaming.

Version 2.0 brings a native macOS Menu Bar application, programmatic packaging, automated ADB port forwarding, secure PIN-based wireless pairing, and an in-app wireless installer for the Android client.

---

## 🚀 Key Features

* **Dual Connection Modes**:
  * **USB Mode**: Wired, high-speed, and ultra-low latency. Auto-configures ADB forwarding silently.
  * **Wi-Fi Mode**: Cable-free streaming over your local Wi-Fi or mobile hotspot. Automatically resolves target IP via default gateways or Bonjour/mDNS.
* **Native macOS App (`Pihu Display.app`)**:
  * Run directly from your `/Applications` directory.
  * Resides cleanly in the system Menu Bar (`LSUIElement`) with no Dock clutter.
  * Elegant dark neon status icon, connection controls, mode selectors, and bitrate options.
* **In-App APK Installer**:
  * Open **Get Android App...** from the status menu to show a native window with a **QR Code**.
  * Spawns an embedded, secure background HTTP server on port 8000 to serve the APK wirelessly.
* **Secure PIN Pairing**:
  * First-time Wi-Fi connections challenge with a 6-digit PIN on the phone.
  * Successful pairings cache a SHA-256 token securely (`SharedPreferences` on Android, JSON cache on macOS) for subsequent password-free connections.
* **Start on Login**:
  * Toggle **Start on Login** in the menu to automatically launch Pihu Display on macOS startup using modern `SMAppService` APIs.

---

## 🛠️ Mac App Installation

You can compile and build the packaged application bundle in one step:

1. Open your terminal and run the packaging script:
   ```bash
   ./scripts/package.sh
   ```
   This will:
   * Compile the macOS host app in release mode.
   * Compile the Android client APK.
   * Package everything into a standalone `dist/Pihu Display.app` bundle complete with a custom app icon and embedded APK.

2. Move **Pihu Display.app** from the `dist/` directory to your **Applications** folder.

3. Double-click to launch it. The screen icon (a dual-monitor system symbol) will appear in your Mac's menu bar.

---

## 📱 Android Client Installation

Pihu Display v2.0 makes installing the Android app on your phone extremely easy and cable-free:

1. Connect your Android phone to the same Wi-Fi/Hotspot network as your Mac.
2. Click the Pihu Display icon in the Mac Menu Bar and select **Get Android App...**
3. Scan the displayed **QR Code** with your phone's camera (or open the printed URL `http://<mac-ip>:8000/` in your phone's browser).
4. Download and install `pihu-display.apk` on your device.
5. Close the window on your Mac when done (this automatically stops the background HTTP server).

*Note: Ensure **USB Debugging** is enabled in your Android developer settings if you plan to use USB mode.*

---

## 🎮 How to Use

### Wi-Fi Mode (Wireless)
1. Open the **Pihu Display** app on your Android phone.
2. On your Mac, click the status bar icon and set **Connection Mode** to **Wi-Fi Only** (or **Auto-Detect**).
3. Click **Start Display**.
4. A popup window will appear on your Mac asking for a pairing code. Enter the **6-digit PIN** displayed on your phone's screen.
5. Mirroring/extension will start immediately. Subsequent connections will connect instantly without prompting for a PIN.

### USB Mode (Wired)
1. Connect your phone to your Mac with a USB cable.
2. On your Mac, select **USB Only** (or **Auto-Detect**) under **Connection Mode**.
3. Click **Start Display**. The app will run ADB port forwarding automatically and start the stream.

### Stream Settings
* **Stream Quality**: Select quality bitrates in the menu:
  * **3 Mbps**: Low bandwidth / fast.
  * **5 Mbps**: Wi-Fi optimized (default for Wi-Fi).
  * **8 Mbps**: Standard USB quality (default for USB).
  * **12 Mbps**: High-quality USB streaming.
* **Auto Aspect Ratio**: The virtual screen automatically resizes itself to match the native aspect ratio of your connected phone's screen.

---

## ⚙️ Requirements & Troubleshooting

* **macOS Host**: Requires macOS 14.0 (Sonoma) or newer (for CoreGraphics Virtual Display and ScreenCaptureKit APIs).
* **Permissions**: On first launch, macOS will prompt you for Screen Recording permissions. Enable it in **System Settings -> Privacy & Security -> Screen & System Audio Recording**.
* **Android Client**: Requires Android 8.0 or newer. A device with a hardware H.264 decoder is recommended.

---

Created with love by Ankit Kumar. Feel free to use and distribute!
