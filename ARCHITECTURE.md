# Pihu Display Technical Architecture

Pihu Display is a low-latency secondary display system that connects a macOS host to an Android client device over USB. This document details the technical implementation, low-level APIs, encoding configuration, transport layer, and rendering pipeline.

---

## Architecture Overview

```
[ macOS Host ] 
  ├── CGVirtualDisplay (CoreGraphics Private API)
  │     └── Creates virtual monitor in macOS Display Manager
  ├── ScreenCaptureKit
  │     └── Captures raw YUV420 frame buffer stream at 60 FPS
  ├── VideoToolbox
  │     └── Encodes frames to H.264 Annex B stream (low-latency profile)
  └── TCP Socket Client
        └── Sends length-prefixed NAL units over TCP localhost

[ USB Transport (ADB) ]
  └── adb forward tcp:27183 tcp:27183
        └── Tunnels TCP traffic from macOS localhost to Android local port

[ Android Client ]
  ├── TCP ServerSocket
  │     └── Listens on port 27183, reads length-prefixed payloads
  ├── MediaCodec (H.264 Hardware Decoder)
  │     └── Decodes H.264 NAL units asynchronously in low-latency mode
  └── SurfaceView
        └── Renders frames directly to display hardware, bypassing standard UI pipeline
```

---

## 1. Virtual Display Creation (macOS Host)

To create a secondary screen on macOS, the host application interacts with the private `CGVirtualDisplay` API (located inside the CoreGraphics framework).

* **Descriptor Configuration**: 
  - Vendor ID: `0x1234`
  - Product ID: `0x5678`
  - Screen dimensions: 1920x1080 (1080p Full HD)
  - Native refresh rate: 60Hz
* **System Integration**: Once initialized, macOS registers this virtual display as a native monitor. Users can configure it as a standalone extended desktop or as a mirror in System Settings -> Displays.

---

## 2. Frame Capture (macOS Host)

Frame capture is implemented using Apple's **ScreenCaptureKit** framework.

* **Filter Configuration**: We define an `SCContentFilter` targeting only the virtual display's screen ID.
* **Frame Buffers**: ScreenCaptureKit outputs raw frame buffers as `CVPixelBuffer` objects.
* **Color Format**: We capture in YUV420 Biplanar format (`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`). This avoids RGB-to-YUV software conversions, matching the input formats expected by the H.264 encoder.
* **Frame Rate & Queue**: Frame capture rate is capped at 60 FPS. The internal capture queue depth is set to `3` to prioritize current frames and discard stale, queued buffers.

---

## 3. Video Encoding (macOS Host)

The raw `CVPixelBuffer` frames are compressed in real-time using Apple's **VideoToolbox** framework.

* **Compression Session**: An instance of `VTCompressionSession` is configured to encode video into H.264 Annex B format.
* **Low-Latency Session Properties**:
  - `kVTCompressionPropertyKey_RealTime`: Set to true to prioritize speed over file compression size.
  - `kVTCompressionPropertyKey_AllowFrameReordering`: Set to false. This disables B-frames (bi-directional predictive frames), ensuring that every frame can be decoded immediately without waiting for future frames, reducing latency.
  - `kVTCompressionPropertyKey_ProfileLevel`: Set to H.264 Main or Baseline profile.
  - `kVTCompressionPropertyKey_MaxKeyFrameInterval`: Forces an I-frame (keyframe) at regular intervals to allow recovery if packets are lost.
* **NAL Unit Packaging**: H.264 output packets contain raw NAL (Network Abstraction Layer) units. The host extracts these units and prepares them for TCP transport.

---

## 4. Transport Layer (ADB & TCP Sockets)

To achieve lowest latency and highest throughput without Wi-Fi congestion or complex network configuration, Pihu Display streams video over a physical USB cable.

* **Tunneling Mechanism**:
  - The Android app starts a TCP `ServerSocket` on local port `27183`.
  - The host script runs `adb forward tcp:27183 tcp:27183`.
  - This redirects all TCP requests targeting localhost port `27183` on the Mac to local port `27183` on the Android device over the ADB USB connection.
* **Framing Protocol**: Since TCP is stream-oriented and does not preserve packet boundaries, a custom framing protocol is used:
  - Header: 4-byte big-endian integer representing the payload size in bytes.
  - Payload: Raw H.264 encoded video frame data (NAL units).
* **Socket Tuning**:
  - `TCP_NODELAY` is enabled on both sockets. This disables Nagle's algorithm, forcing packets to be sent immediately rather than buffered to form larger packets.
  - Send/Receive buffer sizes are set to `1MB` to ensure the OS never blocks due to buffer congestion during high-bitrate keyframes.

---

## 5. Video Decoding & Rendering (Android Client)

On the Android device, the incoming byte stream is read, parsed, decoded, and displayed.

* **Stream Parsing**:
  - The background thread reads the 4-byte header to determine the frame size.
  - It allocates or reuses a byte array of the required length and reads the exact frame payload from the input stream.
* **Hardware Decoder**:
  - The payload is fed into Android's native hardware decoder (`MediaCodec`), configured with the MIME type `video/avc` (H.264).
  - For Android 11+ (API 30+) devices, `KEY_LOW_LATENCY` is set to `1`. This instructs the hardware decoder to output decoded frames immediately without buffering.
* **Asynchronous Execution**:
  - Incoming socket streaming runs on `PihuRxThread`.
  - Decoder output retrieval runs on a separate `PihuDecoderThread`.
  - Both threads run with `Thread.MAX_PRIORITY` to prevent CPU throttling by the Android OS scheduler.
* **Direct Surface Rendering**:
  - The decoded frames are written directly to a hardware-backed `Surface` provided by a `SurfaceView`.
  - This avoids Android's standard UI thread layout/measure passes and Canvas draws, allowing the GPU to display the decoded video frame directly on the screen.
