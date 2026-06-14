import Foundation
import ScreenCaptureKit
import CoreMedia
import VideoToolbox
import CGVirtualDisplayPrivate

class StreamOutputHandler: NSObject, SCStreamOutput, SCStreamDelegate {
    private let encoder: Encoder
    private var isEncoderInitialized = false
    
    init(encoder: Encoder) {
        self.encoder = encoder
    }
    
    private var frameCount = 0
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == SCStreamOutputType.screen else { return }
        
        // 1. Get pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // 2. Initialize or reinitialize encoder if dimensions changed
        if !isEncoderInitialized {
            if encoder.setupSession(width: Int32(width), height: Int32(height)) {
                isEncoderInitialized = true
            }
        }
        
        // 3. Encode frame
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        encoder.encode(pixelBuffer: pixelBuffer, presentationTimeStamp: pts)
        
        frameCount += 1
        if frameCount % 60 == 0 {
            print("[Stream] Captured 60 frames (total: \(frameCount))")
        }
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[Stream] Stopped with error: \(error.localizedDescription)")
    }
}

// Keep the virtual display, stream, and handler objects alive globally
var activeVirtualDisplay: CGVirtualDisplay?
var activeStream: SCStream?
var activeStreamOutputHandler: StreamOutputHandler?

// Top level execution
setbuf(stdout, nil)
print("[PihuDisplayHost] Starting host application...")

// 1. Create the Virtual Display
print("[PihuDisplayHost] Creating virtual display...")
let descriptor = CGVirtualDisplayDescriptor()
descriptor.queue = DispatchQueue(label: "com.pihu.display.virtual", qos: .userInteractive)
descriptor.name = "Pihu Display"
descriptor.sizeInMillimeters = CGSize(width: 330, height: 206) // 15" physical layout
descriptor.maxPixelsWide = 1920
descriptor.maxPixelsHigh = 1080
descriptor.vendorID = 0x1234
descriptor.productID = 0x5678
descriptor.serialNum = 1

let settings = CGVirtualDisplaySettings()
let mode = CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 60)!
settings.modes = [mode]
settings.hiDPI = 1 // 1x scaling to maximize low latency and streaming speed

guard let virtualDisplay = CGVirtualDisplay(descriptor: descriptor) else {
    print("[PihuDisplayHost] Error: Failed to create virtual display. Make sure you run with appropriate permissions.")
    exit(1)
}

if !virtualDisplay.applySettings(settings) {
    print("[PihuDisplayHost] WARNING: Failed to apply settings to virtual display.")
}

activeVirtualDisplay = virtualDisplay
let virtualDisplayID = virtualDisplay.displayID
print("[PihuDisplayHost] Successfully created Virtual Display with ID: \(virtualDisplayID)")

// 2. Start the TCP Client
let port: UInt16 = 27183
let client = TCPClient(port: port)
client.start()

var encodedCount = 0
let encoder = Encoder { data in
    encodedCount += 1
    if encodedCount % 60 == 0 {
        print("[Encoder] Encoded & sent 60 frames (last size: \(data.count) bytes)")
    }
    var length = UInt32(data.count).bigEndian
    let lengthData = Data(bytes: &length, count: 4)
    client.send(data: lengthData)
    client.send(data: data)
}

let handler = StreamOutputHandler(encoder: encoder)

// We run the capture logic in a Task to allow top-level concurrency
let semaphore = DispatchSemaphore(value: 0)

Task {
    do {
        // Check for screen recording permission first
        let hasPermission = CGRequestScreenCaptureAccess()
        if !hasPermission {
            print("[PihuDisplayHost] WARNING: Screen recording permission is not granted.")
            print("[PihuDisplayHost] Please grant screen recording permission in System Settings -> Privacy & Security -> Screen & System Audio Recording.")
        }
        
        // 3. Fetch shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        
        // 4. Find our virtual display specifically
        guard let display = content.displays.first(where: { $0.displayID == virtualDisplayID }) else {
            print("[PihuDisplayHost] Error: Virtual display ID \(virtualDisplayID) not found in ScreenCaptureKit.")
            semaphore.signal()
            return
        }
        
        print("[PihuDisplayHost] Capturing virtual display: \(display.width)x\(display.height)")
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // 5. Configure capture stream settings
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        
        // Set 60 FPS
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        
        // Use YUV420 pixel format for hardware compression optimization
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        
        // Keep queue depth small to minimize latency
        config.queueDepth = 3
        
        // 6. Create and start stream
        let stream = SCStream(filter: filter, configuration: config, delegate: handler)
        try stream.addStreamOutput(handler, type: SCStreamOutputType.screen, sampleHandlerQueue: DispatchQueue(label: "com.pihu.display.capture"))
        
        try await stream.startCapture()
        activeStream = stream
        activeStreamOutputHandler = handler
        print("[PihuDisplayHost] Screen capture of virtual display started successfully!")
        print("[PihuDisplayHost] You can configure mirroring or extension in System Settings -> Displays.")
        print("[PihuDisplayHost] Press Ctrl+C to stop.")
        
    } catch {
        print("[PihuDisplayHost] Error starting screen capture: \(error.localizedDescription)")
        semaphore.signal()
    }
}

// Block main thread to keep process alive until terminated
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: DispatchQueue.main)
sigintSource.setEventHandler {
    print("\n[PihuDisplayHost] Shutting down...")
    if let stream = activeStream {
        Task {
            try? await stream.stopCapture()
        }
    }
    client.stop()
    encoder.teardownSession()
    activeStream = nil
    activeStreamOutputHandler = nil
    activeVirtualDisplay = nil // Destroy virtual display
    exit(0)
}
signal(SIGINT, SIG_IGN)
sigintSource.resume()

semaphore.wait()
