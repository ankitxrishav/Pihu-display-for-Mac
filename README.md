# Pihu Display 🐱

Pihu Display is a high-performance, ultra-low-latency systems application that turns any Android phone or tablet into a **wired secondary monitor for macOS** using only a USB cable and ADB. 

Unlike traditional screen-sharing apps that rely on Wi-Fi, Pihu Display achieves **target latency of <40ms at 60 FPS** by leveraging hardware-accelerated video pipelines and direct USB socket communication.

---

## 🏗️ Technical Architecture

Pihu Display is designed as a low-level systems pipeline:

```
macOS Host (PihuDisplayHost)                 Android Client (Pihu Display App)
┌──────────────────────────────────────┐     ┌──────────────────────────────────┐
│  CGVirtualDisplay (Virtual Screen)   │     │  TCP ServerSocket (Port 27183)   │
│                  ↓                   │     │               ↓                  │
│  ScreenCaptureKit (Frame Capture)   │ ──> │  Length-Prefixed Packet Reader   │
│                  ↓                   │ USB │               ↓                  │
│  VideoToolbox (Hardware H.264)       │     │  MediaCodec (Hardware Decoder)   │
│                  ↓                   │     │               ↓                  │
│  TCP Client (Low-Latency Streamer)   │     │  SurfaceView (Direct Renderer)   │
└──────────────────────────────────────┘     └──────────────────────────────────┘
```

### 1. macOS Host App (`mac-host/`)
- **Virtual Display**: Uses macOS 14+ private `CGVirtualDisplay` APIs to register a native virtual monitor in System Settings.
- **Frame Capture**: Leverages `ScreenCaptureKit` to capture the virtual screen's framebuffer stream at 60 FPS.
- **Hardware Encoding**: Feeds raw `CVPixelBuffer` frames into Apple's `VideoToolbox` (`VTCompressionSession`) for real-time H.264 encoding with low-latency properties (disabling B-frames, sub-frame delay).
- **USB Tunnel**: Sends length-prefixed H.264 video packets over local port forwarding via a TCP socket.

### 2. Transport Layer (`adb forward`)
- Redirects traffic from the Mac's localhost port `27183` to the Android device over USB.
- Bypasses Android network and loopback restrictions that often break `adb reverse`, ensuring highly reliable connectivity.

### 3. Android Client App (`android-client/`)
- **ServerSocket**: Hosts a local TCP server waiting for connection from the Mac host.
- **Packet Parser**: Reads length-prefixed frame payloads, avoiding expensive byte-by-byte string searches.
- **Hardware Decoding**: Feeds raw packets into Android's `MediaCodec` H.264 hardware decoder, configured with `KEY_LOW_LATENCY = 1` (on Android 11+).
- **Direct Renderer**: Renders decoded frames directly to a `SurfaceView` overlay to bypass Android's standard UI thread composition and minimize layout latency.

---

## 🛠️ Prerequisites

- **macOS**: macOS 14 (Sonoma) or newer.
- **Android Device**: Android 8.0 (API 26) or newer.
- **USB Cable**: USB debugging enabled in Developer Options.
- **JDK**: OpenJDK 17 installed on the Mac (required to build the APK).
- **ADB**: Android Debug Bridge installed (e.g. via Homebrew: `brew install android-platform-tools`).

---

## 🚀 How to Run

1. Connect your Android device to your Mac via USB.
2. Verify the device is connected and authorized:
   ```bash
   adb devices
   ```
3. Run the orchestrator script from the project root:
   ```bash
   ./run.sh
   ```
   *This script compiles the macOS host, builds the Android APK, installs/launches it, sets up the USB port forwarding, and starts streaming.*
4. Arrange display positions or configure **Mirroring/Extension** under **System Settings -> Displays** on your Mac.

---

Created with love by Ankit Kumar for personal use feel free to use it.
