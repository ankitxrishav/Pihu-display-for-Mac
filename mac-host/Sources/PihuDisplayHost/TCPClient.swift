import Foundation
import Darwin
import AppKit

struct HandshakeRequest: Codable {
    let client_id: String
    let token: String
}

struct HandshakeResponse: Codable {
    let status: String
    let token: String?
    let device_name: String?
    let width: UInt32?
    let height: UInt32?
    let reason: String?
}

struct PinRequest: Codable {
    let pin: String
}

class TCPClient {
    private let host: String
    private let port: UInt16
    private let pairPin: String?
    private var clientSocket: Int32 = -1
    private let queue = DispatchQueue(label: "com.pihu.display.client")
    private var isRunning = false
    
    private let lock = NSLock()
    private var _isConnected = false
    private var isConnected: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isConnected
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isConnected = newValue
        }
    }
    
    init(host: String = "127.0.0.1", port: UInt16, pairPin: String? = nil) {
        self.host = host
        self.port = port
        self.pairPin = pairPin
    }
    
    func start() {
        if isRunning { return }
        isRunning = true
        queue.async { [weak self] in
            self?.run()
        }
    }
    
    func stop() {
        isRunning = false
        disconnect()
    }
    
    private func disconnect() {
        isConnected = false
        if clientSocket != -1 {
            close(clientSocket)
            clientSocket = -1
            print("[Client] Disconnected from Android server.")
        }
    }
    
    private func run() {
        while isRunning {
            if clientSocket == -1 {
                print("[Client] Attempting to connect to Android server at \(host):\(port)...")
                
                let sock = socket(AF_INET, SOCK_STREAM, 0)
                guard sock >= 0 else {
                    print("[Client] Failed to create socket.")
                    Thread.sleep(forTimeInterval: 2)
                    continue
                }
                
                // Disable Nagle's algorithm for lowest latency
                var noDelay: Int32 = 1
                setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, &noDelay, socklen_t(MemoryLayout<Int32>.size))
                
                // Set socket send buffer to 1MB
                var sendBufSize: Int32 = 1024 * 1024
                setsockopt(sock, SOL_SOCKET, SO_SNDBUF, &sendBufSize, socklen_t(MemoryLayout<Int32>.size))
                
                // Prevent SIGPIPE on macOS socket writes
                var noSigPipe: Int32 = 1
                setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
                
                var addr = sockaddr_in()
                addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = port.bigEndian
                addr.sin_addr.s_addr = inet_addr(host)
                
                let connectResult = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                
                if connectResult >= 0 {
                    print("[Client] TCP connection established. Starting handshake...")
                    
                    // Set a read timeout of 10 seconds for the handshake/pairing flow
                    var timeout = timeval()
                    timeout.tv_sec = 60 // Allow up to 60 seconds for pairing PIN entry
                    timeout.tv_usec = 0
                    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                    
                    if performHandshake(sock: sock) {
                        // Reset timeout to infinite / default after handshake
                        var noTimeout = timeval()
                        noTimeout.tv_sec = 0
                        noTimeout.tv_usec = 0
                        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &noTimeout, socklen_t(MemoryLayout<timeval>.size))
                        
                        self.clientSocket = sock
                        self.isConnected = true
                    } else {
                        close(sock)
                        Thread.sleep(forTimeInterval: 2)
                    }
                } else {
                    let errStr = String(cString: strerror(errno))
                    print("[Client] Connect failed to \(host):\(port) with error: \(errStr) (errno: \(errno))")
                    close(sock)
                    Thread.sleep(forTimeInterval: 2)
                }
            } else {
                Thread.sleep(forTimeInterval: 1)
            }
        }
    }
    
    private func performHandshake(sock: Int32) -> Bool {
        // 1. Send HandshakeRequest
        let clientID = PairingStore.shared.getClientID()
        let token = PairingStore.shared.getToken(forDevice: "WiFi-Device") ?? "" // We will dynamically update key later
        let req = HandshakeRequest(client_id: clientID, token: token)
        
        guard let reqData = try? JSONEncoder().encode(req) else {
            print("[Client] Handshake serialization failed.")
            return false
        }
        
        guard sendLengthPrefixedData(sock: sock, data: reqData) else {
            print("[Client] Failed to send handshake request.")
            return false
        }
        
        // 2. Read HandshakeResponse
        guard let respData = readLengthPrefixedData(sock: sock) else {
            print("[Client] Handshake response timeout or disconnect.")
            return false
        }
        
        guard let response = try? JSONDecoder().decode(HandshakeResponse.self, from: respData) else {
            print("[Client] Failed to decode handshake response.")
            return false
        }
        
        if response.status == "success" {
            return handleHandshakeSuccess(response: response)
        } else if response.status == "pairing_required" {
            print("[Client] Secure pairing required.")
            
            // Prompt for PIN
            let pin: String
            if let pairPin = self.pairPin {
                pin = pairPin
                print("[Client] Using pairing PIN provided in command line: \(pin)")
            } else {
                pin = promptForPIN()
            }
            
            let pinReq = PinRequest(pin: pin)
            guard let pinData = try? JSONEncoder().encode(pinReq) else { return false }
            
            guard sendLengthPrefixedData(sock: sock, data: pinData) else {
                print("[Client] Failed to send PIN request.")
                return false
            }
            
            // Read second response
            guard let secRespData = readLengthPrefixedData(sock: sock) else {
                print("[Client] PIN response timeout.")
                return false
            }
            
            guard let secResponse = try? JSONDecoder().decode(HandshakeResponse.self, from: secRespData) else {
                print("[Client] Failed to decode PIN response.")
                return false
            }
            
            if secResponse.status == "success" {
                return handleHandshakeSuccess(response: secResponse)
            } else {
                print("[Client] Pairing failed: \(secResponse.reason ?? "Unknown error")")
                return false
            }
        } else {
            print("[Client] Handshake rejected: \(response.reason ?? "Unknown error")")
            return false
        }
    }
    
    private func handleHandshakeSuccess(response: HandshakeResponse) -> Bool {
        guard let width = response.width, let height = response.height else {
            print("[Client] Missing dimensions in success response.")
            return false
        }
        
        let deviceName = response.device_name ?? "WiFi-Device"
        print("[Client] Handshake successful with device: \(deviceName) (\(width)x\(height))")
        
        // Cache the token
        if let token = response.token {
            PairingStore.shared.saveToken(token, forDevice: deviceName)
            // Keep a general fallback for the device if SSID changes
            PairingStore.shared.saveToken(token, forDevice: "WiFi-Device")
        }
        
        // Notify host application of the new dimensions
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("PihuAndroidScreenSizeReceived"),
                object: nil,
                userInfo: ["width": width, "height": height]
            )
        }
        return true
    }
    
    private func promptForPIN() -> String {
        var pin: String = ""
        DispatchQueue.main.sync {
            let alert = NSAlert()
            alert.messageText = "Pairing Required"
            alert.informativeText = "Enter the 6-digit PIN shown on your phone's screen:"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Pair")
            alert.addButton(withTitle: "Cancel")
            
            let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            inputTextField.placeholderString = "123456"
            alert.accessoryView = inputTextField
            
            // Force dialog to focus on top
            NSApp.activate(ignoringOtherApps: true)
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                pin = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return pin
    }
    
    func send(data: Data) {
        guard isConnected && clientSocket != -1 else { return }
        _ = sendAll(sock: clientSocket, data: data)
    }
    
    private func sendLengthPrefixedData(sock: Int32, data: Data) -> Bool {
        var length = UInt32(data.count).bigEndian
        let lengthData = Data(bytes: &length, count: 4)
        if !sendAll(sock: sock, data: lengthData) { return false }
        return sendAll(sock: sock, data: data)
    }
    
    private func sendAll(sock: Int32, data: Data) -> Bool {
        return data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            var bytesSent = 0
            let totalBytes = data.count
            
            while bytesSent < totalBytes {
                let result = Darwin.send(sock, baseAddress + bytesSent, totalBytes - bytesSent, 0)
                if result <= 0 {
                    print("[Client] Send failed. Disconnecting...")
                    self.disconnect()
                    return false
                }
                bytesSent += result
            }
            return true
        }
    }
    
    private func recvExactly(sock: Int32, length: Int) -> Data? {
        var buffer = [UInt8](repeating: 0, count: length)
        var totalRead = 0
        
        while totalRead < length {
            var result = 0
            buffer.withUnsafeMutableBytes { rawBufferPointer in
                if let baseAddress = rawBufferPointer.baseAddress {
                    let destPointer = baseAddress.assumingMemoryBound(to: UInt8.self) + totalRead
                    result = recv(sock, destPointer, length - totalRead, 0)
                }
            }
            if result <= 0 {
                return nil
            }
            totalRead += result
        }
        return Data(buffer)
    }
    
    private func readLengthPrefixedData(sock: Int32) -> Data? {
        guard let lengthData = recvExactly(sock: sock, length: 4) else { return nil }
        let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard length > 0, length < 10 * 1024 * 1024 else { return nil }
        return recvExactly(sock: sock, length: Int(length))
    }
}
