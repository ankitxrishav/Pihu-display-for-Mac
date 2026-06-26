# Pihu Display Technical Architecture (v2.0)

Pihu Display is a low-latency secondary display system that connects a macOS host to an Android client device over USB or Wi-Fi. This document details the technical implementation, low-level APIs, encoding configuration, transport layer, and rendering pipeline of Version 2.0.

---

## Architecture Overview

Pihu Display v2.0 operates as a native macOS Menu Bar application that manages virtual display buffers, encodes them using VideoToolbox, and streams them over a custom TCP socket protocol to the Android device.

```
[ Pihu Display macOS App ] 
  ├── CGVirtualDisplay (CoreGraphics)            --> Creates virtual monitor
  ├── ScreenCaptureKit                           --> Captures frame buffer in YUV420 format
  ├── VideoToolbox                               --> Encodes hardware H.264 Annex B stream
  ├── MenuController (AppKit GUI)                --> Resides in status menu bar
  │     ├── SimpleHTTPServer (Swift Sockets)     --> Serves client APK on port 8000
  │     ├── InstallerWindow (AppKit + CoreImage) --> Generates and displays download QR Code
  │     ├── SMAppService (ServiceManagement)     --> Controls Start-on-Login behavior
  │     └── Process (ADB Port Forwarding)        --> Auto forwards port 27183 for USB
  └── TCP Socket Client                          --> Connects to port 27183
        │
   [ USB (ADB) or Wi-Fi (P2P) ]                  --> Transport Layer
        │
[ Pihu Display Android App ]
  ├── NSD Service (_pihu._tcp.)                  --> Broadcasts Bonjour discoverability
  ├── Secure Handshake & PIN Controller          --> Pair authorization challenge
  └── TCP ServerSocket (0.0.0.0:27183)
        └── MediaCodec Hardware Decoder          --> Decodes frames directly to SurfaceView
```

---

## 1. Virtual Display Creation (macOS Host)

To create a secondary screen on macOS, the application interacts with the private `CGVirtualDisplay` API (located inside the CoreGraphics framework).

* **Descriptor Configuration**:
  - Vendor ID: `0x1234`, Product ID: `0x5678`
  - Screen size: Initialized at 1920x1080 (1080p Full HD)
  - Native refresh rate: 60Hz
  - Scaling: Configured with `hiDPI = 1` (1x scaling) to optimize low latency and minimize pixel scaling overhead.
* **Aspect Ratio Auto-Matching**: When the Android client connects, it transmits its physical screen metrics (width and height). The macOS host dynamically computes a resolution matching the exact aspect ratio of the phone (constrained within the 1920x1080 bounding box) and applies it using `virtualDisplay.applySettings()`. This eliminates black letterbox bars on the phone.

---

## 2. Frame Capture & Encoding (macOS Host)

Frame capture and encoding form a hardware-accelerated pipeline running on a background queue.

* **Capture (ScreenCaptureKit)**:
  - An `SCContentFilter` targets the virtual display ID.
  - Frame buffers are captured as `CVPixelBuffer` in YUV420 Biplanar format (`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`). This matches the input format expected by the hardware encoder.
  - The capture queue depth is restricted to `3` to prioritize new frames and discard old ones under CPU stress.
* **Compression (VideoToolbox)**:
  - Raw pixel buffers are fed into a `VTCompressionSession` producing H.264 video.
  - Properties optimized for interactive mirroring:
    - `kVTCompressionPropertyKey_RealTime` = `true` (minimizes latency over compression efficiency).
    - `kVTCompressionPropertyKey_AllowFrameReordering` = `false` (disables B-frames, allowing immediate decoding).
    - `kVTCompressionPropertyKey_ProfileLevel` = H.264 Main/Baseline.

---

## 3. GUI Orchestration & Packaging (v2.0 Updates)

Version 2.0 packages the system utility into a native App Bundle (`Pihu Display.app`) and automates all terminal-based tasks:

### A. Simple HTTP Socket Server (In-App Sideloading)
To allow cable-free installation, `InstallerWindowController` implements a custom `SimpleHTTPServer` written in pure Swift using POSIX sockets:
* Runs on port 8000 and listens on all interfaces (`INADDR_ANY`).
* Reads the raw byte stream of the GET request, validates the URL, and streams `pihu-display.apk` directly from the App Bundle's `Contents/Resources/` directory in 64KB chunks.
* The server operates purely on a background thread (`DispatchQueue` utility class) and terminates instantly when the window is closed to free the port.

### B. Native QR Code Generator
* Using CoreImage's built-in `CIQRCodeGenerator` filter, the app transforms the download URL (`http://<mac-ip>:8000/pihu-display.apk`) into a binary matrix.
* The matrix is scaled up using an affine transform to avoid pixelation, converted into an `NSImage` via `NSCIImageRep`, and displayed programmatically inside an AppKit utility window.

### C. Automatic ADB Forwarding
* In USB mode, the app uses macOS's `Process` API to automatically find the `adb` binary in common developer paths (Homebrew, Android SDK).
* It silently spawns `/path/to/adb forward tcp:27183 tcp:27183` in the background before initiating the client socket connection, achieving true plug-and-play behavior.

### D. Start on Login
* The app integrates macOS's modern `ServiceManagement` (`SMAppService.mainApp`) API. Toggling "Start on Login" registers the application with launchd to start automatically when the user logs in.

---

## 4. Secure Transport & Wi-Fi Discovery

Pihu Display v2.0 supports direct wireless connections over Wi-Fi and mobile hotspots.

* **Bonjour Discovery (mDNS)**:
  - The Android client advertises itself as a Network Service Discovery (NSD) service under the service type `_pihu._tcp.`.
  - The macOS host uses `NetServiceBrowser` to resolve the service broadcast and determine the target IP address.
* **Gateway Guessing (Hotspot)**:
  - If connected to the phone's mobile hotspot, the Mac queries its local routing table (`route -n get default`) to resolve the gateway IP address, bypassing Bonjour lookup times.
* **Pairing and Token Handshake**:
  - The connection challenge prevents unauthorized screen capture.
  - If the client's UUID is not registered in the Android app's `SharedPreferences`, the Android server displays a randomly generated 6-digit PIN code and returns a `pairing_required` JSON payload to the Mac.
  - The Mac prompts the user with an AppKit `NSAlert` input box.
  - Once validated, the Android server generates a secure cryptographically random UUID token, caches it locally, and returns it to the Mac, which saves it under `~/Library/Application Support/PihuDisplay/paired.json`.
  - Subsequent handshakes automatically authenticate using this cached token.

---

## 5. Rendering Pipeline (Android Client)

* **Hardware Decoder**: Incoming bytes are fed directly into Android's native hardware decoder (`MediaCodec`) configured with `KEY_LOW_LATENCY = 1` on Android 11+ to bypass default frame reordering buffers.
* **Direct Surface Rendering**: The decoded frame is output directly onto the hardware `Surface` of a `SurfaceView`. This bypasses the Android View hierarchy's main thread rendering loops, drawing the virtual display frames onto the screen with sub-millisecond drawing latency.
