import Foundation
import AppKit
import ScreenCaptureKit
import CoreMedia
import VideoToolbox
import CGVirtualDisplayPrivate
import ServiceManagement

class MenuController: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let mainQueue = DispatchQueue.main
    
    // State
    private var isStreaming = false
    private var connectionMode: ConnectionMode = .auto
    private var selectedBitrate: Int = 8_000_000
    
    // Core Objects
    private var virtualDisplay: CGVirtualDisplay?
    private var stream: SCStream?
    private var streamOutputHandler: StreamOutputHandler?
    private var client: TCPClient?
    private var encoder: Encoder?
    
    // Menu items
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var modeAutoItem: NSMenuItem!
    private var modeUSBItem: NSMenuItem!
    private var modeWiFiItem: NSMenuItem!
    
    private var bitrate3MItem: NSMenuItem!
    private var bitrate5MItem: NSMenuItem!
    private var bitrate8MItem: NSMenuItem!
    private var bitrate12MItem: NSMenuItem!
    
    private var getAndroidAppItem: NSMenuItem!
    private var startOnLoginItem: NSMenuItem!
    
    override init() {
        super.init()
        
        // Load persisted settings
        let modeVal = UserDefaults.standard.integer(forKey: "PihuConnectionMode") // 0: auto, 1: usb, 2: wifi
        switch modeVal {
        case 1: connectionMode = .usb
        case 2: connectionMode = .wifi
        default: connectionMode = .auto
        }
        
        let bitrateVal = UserDefaults.standard.integer(forKey: "PihuBitrate")
        selectedBitrate = bitrateVal > 0 ? bitrateVal : 8_000_000
        
        setupMenu()
        setupNotificationObserver()
    }
    
    private func setupMenu() {
        if let button = statusItem.button {
            // Set menu bar icon using system symbol "display.2" or simple text if symbol not available
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "Pihu Display")
            } else {
                button.title = "Pihu"
            }
        }
        
        let menu = NSMenu()
        
        // Status Item (Disabled)
        statusMenuItem = NSMenuItem(title: "Status: Disconnected", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Toggle Action
        toggleMenuItem = NSMenuItem(title: "Start Display", action: #selector(toggleDisplay), keyEquivalent: "s")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Mode Submenu
        let modeMenu = NSMenu()
        modeAutoItem = NSMenuItem(title: "Auto-Detect", action: #selector(setModeAuto), keyEquivalent: "")
        modeAutoItem.target = self
        modeUSBItem = NSMenuItem(title: "USB Only", action: #selector(setModeUSB), keyEquivalent: "")
        modeUSBItem.target = self
        modeWiFiItem = NSMenuItem(title: "Wi-Fi Only", action: #selector(setModeWiFi), keyEquivalent: "")
        modeWiFiItem.target = self
        modeMenu.addItem(modeAutoItem)
        modeMenu.addItem(modeUSBItem)
        modeMenu.addItem(modeWiFiItem)
        
        let modeSubMenu = NSMenuItem(title: "Connection Mode", action: nil, keyEquivalent: "")
        modeSubMenu.submenu = modeMenu
        menu.addItem(modeSubMenu)
        
        // Bitrate Submenu
        let bitrateMenu = NSMenu()
        bitrate3MItem = NSMenuItem(title: "3 Mbps (Fast / Low Bandwidth)", action: #selector(setBitrate3M), keyEquivalent: "")
        bitrate3MItem.target = self
        bitrate5MItem = NSMenuItem(title: "5 Mbps (Wi-Fi Optimized)", action: #selector(setBitrate5M), keyEquivalent: "")
        bitrate5MItem.target = self
        bitrate8MItem = NSMenuItem(title: "8 Mbps (Standard USB)", action: #selector(setBitrate8M), keyEquivalent: "")
        bitrate8MItem.target = self
        bitrate12MItem = NSMenuItem(title: "12 Mbps (High Quality USB)", action: #selector(setBitrate12M), keyEquivalent: "")
        bitrate12MItem.target = self
        bitrateMenu.addItem(bitrate3MItem)
        bitrateMenu.addItem(bitrate5MItem)
        bitrateMenu.addItem(bitrate8MItem)
        bitrateMenu.addItem(bitrate12MItem)
        
        let bitrateSubMenu = NSMenuItem(title: "Stream Quality", action: nil, keyEquivalent: "")
        bitrateSubMenu.submenu = bitrateMenu
        menu.addItem(bitrateSubMenu)
        
        menu.addItem(NSMenuItem.separator())
        
        // Get Android App
        getAndroidAppItem = NSMenuItem(title: "Get Android App...", action: #selector(openInstaller), keyEquivalent: "")
        getAndroidAppItem.target = self
        menu.addItem(getAndroidAppItem)
        
        // Start on Login
        startOnLoginItem = NSMenuItem(title: "Start on Login", action: #selector(toggleStartOnLogin), keyEquivalent: "")
        startOnLoginItem.target = self
        menu.addItem(startOnLoginItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit Item
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        updateMenuChecks()
    }
    
    private func updateMenuChecks() {
        // Mode checks
        modeAutoItem.state = connectionMode == .auto ? .on : .off
        modeUSBItem.state = connectionMode == .usb ? .on : .off
        modeWiFiItem.state = connectionMode == .wifi ? .on : .off
        
        // Bitrate checks
        bitrate3MItem.state = selectedBitrate == 3_000_000 ? .on : .off
        bitrate5MItem.state = selectedBitrate == 5_000_000 ? .on : .off
        bitrate8MItem.state = selectedBitrate == 8_000_000 ? .on : .off
        bitrate12MItem.state = selectedBitrate == 12_000_000 ? .on : .off
        
        // Login item check
        if #available(macOS 13.0, *) {
            startOnLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            startOnLoginItem.state = .off
        }
    }
    
    // Actions
    @objc private func setModeAuto() {
        connectionMode = .auto
        UserDefaults.standard.set(0, forKey: "PihuConnectionMode")
        updateMenuChecks()
    }
    
    @objc private func setModeUSB() {
        connectionMode = .usb
        UserDefaults.standard.set(1, forKey: "PihuConnectionMode")
        updateMenuChecks()
    }
    
    @objc private func setModeWiFi() {
        connectionMode = .wifi
        UserDefaults.standard.set(2, forKey: "PihuConnectionMode")
        updateMenuChecks()
    }
    
    @objc private func setBitrate3M() {
        selectedBitrate = 3_000_000
        UserDefaults.standard.set(3_000_000, forKey: "PihuBitrate")
        updateMenuChecks()
    }
    
    @objc private func setBitrate5M() {
        selectedBitrate = 5_000_000
        UserDefaults.standard.set(5_000_000, forKey: "PihuBitrate")
        updateMenuChecks()
    }
    
    @objc private func setBitrate8M() {
        selectedBitrate = 8_000_000
        UserDefaults.standard.set(8_000_000, forKey: "PihuBitrate")
        updateMenuChecks()
    }
    
    @objc private func setBitrate12M() {
        selectedBitrate = 12_000_000
        UserDefaults.standard.set(12_000_000, forKey: "PihuBitrate")
        updateMenuChecks()
    }
    
    @objc private func toggleDisplay() {
        if isStreaming {
            stopStream()
        } else {
            startStream()
        }
    }
    
    @objc private func quitApp() {
        stopStream()
        NSApplication.shared.terminate(self)
    }
    
    @objc private func openInstaller() {
        InstallerWindowController.shared.show()
    }
    
    @objc private func toggleStartOnLogin() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            if service.status == .enabled {
                do {
                    try service.unregister()
                    print("[MenuController] Unregistered login item.")
                } catch {
                    print("[MenuController] Failed to unregister login item: \(error)")
                }
            } else {
                do {
                    try service.register()
                    print("[MenuController] Registered login item.")
                } catch {
                    print("[MenuController] Failed to register login item: \(error)")
                }
            }
            updateMenuChecks()
        }
    }
    
    private func runADBForwardingIfNeeded(targetHost: String) {
        guard targetHost == "127.0.0.1" else { return }
        
        let adbPaths = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb"
        ]
        
        var resolvedAdbPath: String? = nil
        for path in adbPaths {
            if FileManager.default.fileExists(atPath: path) {
                resolvedAdbPath = path
                break
            }
        }
        
        let adbPath = resolvedAdbPath ?? "/opt/homebrew/bin/adb"
        print("[MenuController] Found adb at \(adbPath). Forwarding port 27183...")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["forward", "tcp:27183", "tcp:27183"]
        
        do {
            try process.run()
            process.waitUntilExit()
            print("[MenuController] ADB port forwarding command finished.")
        } catch {
            print("[MenuController] Failed to run ADB forwarding: \(error.localizedDescription)")
        }
    }
    
    private func updateStatus(_ text: String, isWorking: Bool = false) {
        mainQueue.async { [weak self] in
            guard let self = self else { return }
            self.statusMenuItem.title = "Status: \(text)"
            if isWorking {
                if #available(macOS 11.0, *) {
                    self.statusItem.button?.image = NSImage(systemSymbolName: "display.and.arrow.down", accessibilityDescription: "Pihu Display")
                }
            } else {
                if #available(macOS 11.0, *) {
                    self.statusItem.button?.image = NSImage(systemSymbolName: self.isStreaming ? "display.2" : "display", accessibilityDescription: "Pihu Display")
                }
            }
        }
    }
    
    private func startStream() {
        isStreaming = true
        toggleMenuItem.title = "Stop Display"
        updateStatus("Connecting...", isWorking: true)
        
        Task {
            // 1. Resolve Target IP Address
            guard let targetHost = NetworkDiscovery.resolveAddress(mode: connectionMode, manualHost: nil) else {
                showErrorAlert(message: "Could not resolve target device address. Please ensure a device is connected via USB or is reachable on the local Wi-Fi/Hotspot network.")
                self.stopStream()
                return
            }
            
            self.runADBForwardingIfNeeded(targetHost: targetHost)
            
            let isWifi = (targetHost != "127.0.0.1")
            let activeBitrate = isWifi ? min(selectedBitrate, 5_000_000) : selectedBitrate
            print("[MenuController] Connecting to host: \(targetHost), Bitrate: \(activeBitrate) bps")
            
            // 2. Start the TCP Client
            let port: UInt16 = 27183
            let client = TCPClient(host: targetHost, port: port, pairPin: nil)
            self.client = client
            client.start()
            
            // 3. Setup Encoder
            let encoder = Encoder(bitrate: activeBitrate) { [weak self] data in
                guard let self = self, let client = self.client else { return }
                var length = UInt32(data.count).bigEndian
                let lengthData = Data(bytes: &length, count: 4)
                client.send(data: lengthData)
                client.send(data: data)
            }
            self.encoder = encoder
            
            let handler = StreamOutputHandler(encoder: encoder)
            self.streamOutputHandler = handler
            
            // 4. Create the Virtual Display
            print("[MenuController] Creating virtual display...")
            let descriptor = CGVirtualDisplayDescriptor()
            descriptor.queue = DispatchQueue(label: "com.pihu.display.virtual", qos: .userInteractive)
            descriptor.name = "Pihu Display"
            descriptor.sizeInMillimeters = CGSize(width: 330, height: 206)
            descriptor.maxPixelsWide = 1920
            descriptor.maxPixelsHigh = 1080
            descriptor.vendorID = 0x1234
            descriptor.productID = 0x5678
            descriptor.serialNum = 1
            
            let settings = CGVirtualDisplaySettings()
            let mode = CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 60)!
            settings.modes = [mode]
            settings.hiDPI = 1
            
            guard let virtualDisplay = CGVirtualDisplay(descriptor: descriptor) else {
                showErrorAlert(message: "Failed to create virtual display. Make sure you run with appropriate permissions.")
                self.stopStream()
                return
            }
            
            if !virtualDisplay.applySettings(settings) {
                print("[MenuController] WARNING: Failed to apply settings to virtual display.")
            }
            
            self.virtualDisplay = virtualDisplay
            let virtualDisplayID = virtualDisplay.displayID
            print("[MenuController] Successfully created Virtual Display with ID: \(virtualDisplayID)")
            
            // 5. Start Capture
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == virtualDisplayID }) else {
                    showErrorAlert(message: "Virtual display ID \(virtualDisplayID) not found in ScreenCaptureKit.")
                    self.stopStream()
                    return
                }
                
                print("[MenuController] Capturing virtual display: \(display.width)x\(display.height)")
                
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width
                config.height = display.height
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                config.queueDepth = 3
                
                let stream = SCStream(filter: filter, configuration: config, delegate: handler)
                try stream.addStreamOutput(handler, type: SCStreamOutputType.screen, sampleHandlerQueue: DispatchQueue(label: "com.pihu.display.capture"))
                
                try await stream.startCapture()
                self.stream = stream
                
                self.updateStatus("Streaming to phone")
                print("[MenuController] Screen capture of virtual display started successfully!")
                
            } catch {
                showErrorAlert(message: "Error starting screen capture: \(error.localizedDescription)")
                self.stopStream()
            }
        }
    }
    
    private func stopStream() {
        isStreaming = false
        toggleMenuItem.title = "Start Display"
        updateStatus("Disconnected")
        
        if let stream = stream {
            Task {
                try? await stream.stopCapture()
            }
        }
        
        client?.stop()
        encoder?.teardownSession()
        
        stream = nil
        client = nil
        encoder = nil
        streamOutputHandler = nil
        virtualDisplay = nil // Destroy virtual display
        
        print("[MenuController] Stream stopped and virtual display destroyed.")
    }
    
    // Dynamic Resolution Updater (same logic as in main.swift)
    private func updateVirtualDisplayResolution(phoneWidth: UInt32, phoneHeight: UInt32) {
        guard let virtualDisplay = virtualDisplay else { return }
        
        let aspect = Double(phoneWidth) / Double(phoneHeight)
        let finalWidth: Int32
        let finalHeight: Int32
        
        let maxW: Double = 1920.0
        let maxH: Double = 1080.0
        
        if aspect > (maxW / maxH) {
            let w = maxW
            let h = w / aspect
            let wInt = Int32(round(w))
            let hInt = Int32(round(h))
            finalWidth = (wInt % 2 == 0) ? wInt : wInt - 1
            finalHeight = (hInt % 2 == 0) ? hInt : hInt - 1
        } else {
            let h = maxH
            let w = h * aspect
            let wInt = Int32(round(w))
            let hInt = Int32(round(h))
            finalWidth = (wInt % 2 == 0) ? wInt : wInt - 1
            finalHeight = (hInt % 2 == 0) ? hInt : hInt - 1
        }
        
        print("[MenuController] Adjusting display resolution to: \(finalWidth)x\(finalHeight)")
        
        let settings = CGVirtualDisplaySettings()
        guard let mode = CGVirtualDisplayMode(width: UInt32(finalWidth), height: UInt32(finalHeight), refreshRate: 60) else { return }
        settings.modes = [mode]
        settings.hiDPI = 1
        
        if virtualDisplay.applySettings(settings) {
            Task {
                if let stream = self.stream {
                    try? await stream.stopCapture()
                }
                
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                    guard let display = content.displays.first(where: { $0.displayID == virtualDisplay.displayID }),
                          let handler = self.streamOutputHandler else { return }
                    
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    config.width = display.width
                    config.height = display.height
                    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                    config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                    config.queueDepth = 3
                    
                    let stream = SCStream(filter: filter, configuration: config, delegate: handler)
                    try stream.addStreamOutput(handler, type: SCStreamOutputType.screen, sampleHandlerQueue: DispatchQueue(label: "com.pihu.display.capture"))
                    
                    try await stream.startCapture()
                    self.stream = stream
                    print("[MenuController] Screen capture restarted successfully at \(display.width)x\(display.height)!")
                } catch {
                    print("[MenuController] Error restarting screen capture: \(error)")
                }
            }
        }
    }
    
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("PihuAndroidScreenSizeReceived"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let phoneWidth = userInfo["width"] as? UInt32,
                  let phoneHeight = userInfo["height"] as? UInt32 else { return }
            
            self.updateStatus("Streaming to phone")
            self.updateVirtualDisplayResolution(phoneWidth: phoneWidth, phoneHeight: phoneHeight)
        }
    }
    
    private func showErrorAlert(message: String) {
        mainQueue.async {
            let alert = NSAlert()
            alert.messageText = "Pihu Display Error"
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
