import Foundation
import AppKit
import CoreImage

class SimpleHTTPServer {
    private var listenSocket: Int32 = -1
    private let queue = DispatchQueue(label: "com.pihu.display.http", qos: .utility)
    private var isRunning = false
    private let apkPath: String
    private let port: UInt16
    
    init(apkPath: String, port: UInt16 = 8000) {
        self.apkPath = apkPath
        self.port = port
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        queue.async { [weak self] in
            self?.run()
        }
    }
    
    func stop() {
        isRunning = false
        if listenSocket != -1 {
            close(listenSocket)
            listenSocket = -1
            print("[HTTPServer] Stopped listening.")
        }
    }
    
    private func run() {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            print("[HTTPServer] Error creating socket.")
            return
        }
        listenSocket = sock
        
        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        
        var addr = sockaddr_in()
        addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian
        
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard bindResult >= 0 else {
            print("[HTTPServer] Bind failed on port \(port).")
            close(sock)
            listenSocket = -1
            return
        }
        
        guard listen(sock, 5) >= 0 else {
            print("[HTTPServer] Listen failed.")
            close(sock)
            listenSocket = -1
            return
        }
        
        print("[HTTPServer] Listening on port \(port), serving: \(apkPath)")
        
        while isRunning {
            var clientAddr = sockaddr()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr>.size)
            let clientSock = accept(sock, &clientAddr, &clientAddrLen)
            
            guard clientSock >= 0 else {
                if !isRunning { break }
                continue
            }
            
            // Handle client connection
            DispatchQueue.global(qos: .utility).async {
                self.handleClient(clientSock)
            }
        }
    }
    
    private func handleClient(_ clientSock: Int32) {
        defer { close(clientSock) }
        
        var buffer = [UInt8](repeating: 0, count: 1024)
        let bytesRead = recv(clientSock, &buffer, buffer.count - 1, 0)
        guard bytesRead > 0 else { return }
        
        let requestStr = String(decoding: buffer.prefix(bytesRead), as: UTF8.self)
        let lines = requestStr.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return }
        
        let path = parts[1]
        // Serve the APK for any request ending in .apk or the root path `/`
        if path == "/" || path.hasSuffix(".apk") {
            guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: apkPath)) else {
                print("[HTTPServer] Error: Could not read APK file at \(apkPath)")
                let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                _ = response.withCString { send(clientSock, $0, strlen($0), 0) }
                return
            }
            
            let headers = "HTTP/1.1 200 OK\r\n" +
                          "Content-Type: application/vnd.android.package-archive\r\n" +
                          "Content-Length: \(fileData.count)\r\n" +
                          "Content-Disposition: attachment; filename=\"pihu-display.apk\"\r\n" +
                          "Connection: close\r\n\r\n"
            
            _ = headers.withCString { send(clientSock, $0, strlen($0), 0) }
            
            fileData.withUnsafeBytes { rawBuffer in
                if let baseAddress = rawBuffer.baseAddress {
                    var bytesSent = 0
                    while bytesSent < fileData.count {
                        let chunk = min(fileData.count - bytesSent, 65536) // Send in 64KB chunks
                        let sent = send(clientSock, baseAddress + bytesSent, chunk, 0)
                        if sent <= 0 {
                            print("[HTTPServer] Send failed or client disconnected.")
                            break
                        }
                        bytesSent += sent
                    }
                }
            }
            print("[HTTPServer] Successfully served APK (\(fileData.count) bytes)")
        } else {
            let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            _ = response.withCString { send(clientSock, $0, strlen($0), 0) }
        }
    }
}

class InstallerWindowController: NSObject, NSWindowDelegate {
    static let shared = InstallerWindowController()
    
    private var window: NSWindow?
    private var server: SimpleHTTPServer?
    
    private override init() {
        super.init()
    }
    
    func show() {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Find APK path
        var apkPath: String? = nil
        if let bundlePath = Bundle.main.path(forResource: "pihu-display", ofType: "apk") {
            apkPath = bundlePath
        } else if FileManager.default.fileExists(atPath: "./dist/pihu-display.apk") {
            apkPath = "./dist/pihu-display.apk"
        } else if FileManager.default.fileExists(atPath: "../dist/pihu-display.apk") {
            apkPath = "../dist/pihu-display.apk"
        }
        
        guard let resolvedApkPath = apkPath else {
            let alert = NSAlert()
            alert.messageText = "APK Not Found"
            alert.informativeText = "Could not locate 'pihu-display.apk' in the app resources or 'dist/' directory. Make sure you build the APK first."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        
        // Resolve local IP
        let localIP = NetworkDiscovery.getLocalIPAddress() ?? "127.0.0.1"
        let downloadURL = "http://\(localIP):8000/pihu-display.apk"
        
        // Start HTTP Server
        server = SimpleHTTPServer(apkPath: resolvedApkPath, port: 8000)
        server?.start()
        
        // Create NSWindow Programmatically
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        let rect = NSRect(x: 0, y: 0, width: 450, height: 420)
        let newWindow = NSWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
        newWindow.title = "Pihu Display — Install Android Client"
        newWindow.delegate = self
        newWindow.backgroundColor = .windowBackgroundColor
        newWindow.center()
        
        // Setup Views programmatically with modern design
        let contentView = NSView(frame: rect)
        newWindow.contentView = contentView
        
        // 1. Title Label
        let titleLabel = NSTextField(labelWithString: "Install Pihu Display on Android")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 20, y: 370, width: 410, height: 30)
        titleLabel.alignment = .center
        contentView.addSubview(titleLabel)
        
        // 2. Instructions
        let instructions = "1. Connect your Android phone to this Mac's Wi-Fi network/Hotspot.\n2. Scan this QR code or open the link below in your phone's browser to download and install the app."
        let instLabel = NSTextField(wrappingLabelWithString: instructions)
        instLabel.font = NSFont.systemFont(ofSize: 13)
        instLabel.textColor = .secondaryLabelColor
        instLabel.frame = NSRect(x: 30, y: 290, width: 390, height: 60)
        instLabel.alignment = .left
        contentView.addSubview(instLabel)
        
        // 3. QR Code NSImageView
        let qrImageView = NSImageView(frame: NSRect(x: 125, y: 70, width: 200, height: 200))
        if let qrImage = generateQRCode(from: downloadURL) {
            qrImageView.image = qrImage
        }
        contentView.addSubview(qrImageView)
        
        // 4. URL Link Label
        let linkLabel = NSTextField(labelWithString: downloadURL)
        linkLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        linkLabel.textColor = .linkColor
        linkLabel.frame = NSRect(x: 20, y: 40, width: 410, height: 20)
        linkLabel.alignment = .center
        contentView.addSubview(linkLabel)
        
        // 5. Server status indicator
        let statusLabel = NSTextField(labelWithString: "● Local server active")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .systemGreen
        statusLabel.frame = NSRect(x: 20, y: 15, width: 410, height: 20)
        statusLabel.alignment = .center
        contentView.addSubview(statusLabel)
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowWillClose(_ notification: Notification) {
        server?.stop()
        server = nil
        window = nil
        print("[InstallerWindow] Closed and server stopped.")
    }
    
    private func generateQRCode(from string: String) -> NSImage? {
        let data = string.data(using: .utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let ciImage = filter.outputImage else { return nil }
        
        let scaleX = 200.0 / ciImage.extent.size.width
        let scaleY = 200.0 / ciImage.extent.size.height
        let transformedImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        let rep = NSCIImageRep(ciImage: transformedImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
