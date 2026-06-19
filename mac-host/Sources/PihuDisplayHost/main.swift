import Foundation
import ScreenCaptureKit
import CoreMedia
import VideoToolbox
import CGVirtualDisplayPrivate

class StreamOutputHandler: NSObject, SCStreamOutput, SCStreamDelegate {
    private let encoder: Encoder
    private var isEncoderInitialized = false
    private var currentWidth: Int32 = 0
    private var currentHeight: Int32 = 0
    
    init(encoder: Encoder) {
        self.encoder = encoder
    }
    
    private var frameCount = 0
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == SCStreamOutputType.screen else { return }
        
        // 1. Get pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int32(CVPixelBufferGetHeight(pixelBuffer))
        
        // 2. Initialize or reinitialize encoder if dimensions changed
        if !isEncoderInitialized || width != currentWidth || height != currentHeight {
            print("[Stream] Screen dimensions changed or encoder not initialized. New size: \(width)x\(height)")
            if isEncoderInitialized {
                encoder.teardownSession()
                isEncoderInitialized = false
            }
            if encoder.setupSession(width: width, height: height) {
                isEncoderInitialized = true
                currentWidth = width
                currentHeight = height
            } else {
                print("[Stream] Failed to setup encoder session for \(width)x\(height)")
                return
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
descriptor.maxPixelsWide = 2560
descriptor.maxPixelsHigh = 1600
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

// 7. Dynamic Resolution Updater based on client aspect ratio
func updateVirtualDisplayResolution(phoneWidth: UInt32, phoneHeight: UInt32) {
    guard let virtualDisplay = activeVirtualDisplay else { return }
    
    // Calculate aspect ratio
    let aspect = Double(phoneWidth) / Double(phoneHeight)
    
    // Target display height is capped at 1080 for coding/decoding efficiency,
    // keeping the exact aspect ratio of the phone screen.
    let targetHeight: Double = 1080.0
    let targetWidth = targetHeight * aspect
    
    let w = Int32(round(targetWidth))
    // Make sure width is even, as H.264 encoding requires even dimensions!
    let finalWidth = (w % 2 == 0) ? w : w - 1
    let finalHeight = Int32(targetHeight)
    
    print("[PihuDisplayHost] Updating virtual display resolution to match phone aspect ratio: \(finalWidth)x\(finalHeight) (Phone: \(phoneWidth)x\(phoneHeight))")
    
    let settings = CGVirtualDisplaySettings()
    guard let mode = CGVirtualDisplayMode(width: UInt32(finalWidth), height: UInt32(finalHeight), refreshRate: 60) else {
        print("[PihuDisplayHost] Error: Failed to create CGVirtualDisplayMode for \(finalWidth)x\(finalHeight)")
        return
    }
    settings.modes = [mode]
    settings.hiDPI = 1
    
    if virtualDisplay.applySettings(settings) {
        print("[PihuDisplayHost] Successfully applied new display resolution settings.")
        
        // Restart capture stream to pick up the new resolution
        Task {
            if let stream = activeStream {
                do {
                    try await stream.stopCapture()
                    print("[PihuDisplayHost] Stopped old capture stream.")
                } catch {
                    print("[PihuDisplayHost] Error stopping capture stream: \(error)")
                }
            }
            
            // Re-create the stream configuration with new dimensions
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == virtualDisplay.displayID }) else {
                    print("[PihuDisplayHost] Error: Virtual display not found for recreation.")
                    return
                }
                
                print("[PihuDisplayHost] Re-capturing virtual display: \(display.width)x\(display.height)")
                
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width
                config.height = display.height
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                config.queueDepth = 3
                
                let handler = StreamOutputHandler(encoder: encoder)
                let stream = SCStream(filter: filter, configuration: config, delegate: handler)
                try stream.addStreamOutput(handler, type: SCStreamOutputType.screen, sampleHandlerQueue: DispatchQueue(label: "com.pihu.display.capture"))
                
                try await stream.startCapture()
                activeStream = stream
                activeStreamOutputHandler = handler
                print("[PihuDisplayHost] Screen capture restarted successfully at \(display.width)x\(display.height)!")
            } catch {
                print("[PihuDisplayHost] Error restarting screen capture: \(error)")
            }
        }
    } else {
        print("[PihuDisplayHost] WARNING: Failed to apply settings to virtual display.")
    }
}

NotificationCenter.default.addObserver(
    forName: Notification.Name("PihuAndroidScreenSizeReceived"),
    object: nil,
    queue: .main
) { notification in
    guard let userInfo = notification.userInfo,
          let phoneWidth = userInfo["width"] as? UInt32,
          let phoneHeight = userInfo["height"] as? UInt32 else { return }
    
    updateVirtualDisplayResolution(phoneWidth: phoneWidth, phoneHeight: phoneHeight)
}

semaphore.wait()
