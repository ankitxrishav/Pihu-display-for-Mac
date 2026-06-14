import Foundation
import Darwin

class TCPClient {
    private let host: String
    private let port: UInt16
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
    
    init(host: String = "127.0.0.1", port: UInt16) {
        self.host = host
        self.port = port
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
                    print("[Client] Connected to Android server successfully!")
                    self.clientSocket = sock
                    self.isConnected = true
                } else {
                    close(sock)
                    Thread.sleep(forTimeInterval: 2)
                }
            } else {
                Thread.sleep(forTimeInterval: 1)
            }
        }
    }
    
    func send(data: Data) {
        guard isConnected && clientSocket != -1 else { return }
        
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var bytesSent = 0
            let totalBytes = data.count
            
            while bytesSent < totalBytes {
                let result = Darwin.send(clientSocket, baseAddress + bytesSent, totalBytes - bytesSent, 0)
                if result <= 0 {
                    print("[Client] Send failed. Disconnecting...")
                    self.disconnect()
                    break
                }
                bytesSent += result
            }
        }
    }
}
