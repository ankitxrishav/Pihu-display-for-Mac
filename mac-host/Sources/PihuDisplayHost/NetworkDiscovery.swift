import Foundation
import Darwin

enum ConnectionMode {
    case usb
    case wifi
    case auto
}

class NetworkDiscovery {
    
    static func getGatewayIP() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "route -n get default | awk '/gateway/{print $2}'"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let gateway = output.trimmingCharacters(in: .whitespacesAndNewlines)
                // Basic validation for IPv4
                let parts = gateway.split(separator: ".")
                if parts.count == 4, parts.allSatisfy({ Int($0) != nil }) {
                    return gateway
                }
            }
        } catch {
            print("[Discovery] Error getting gateway IP: \(error)")
        }
        return nil
    }
    
    static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                guard let interface = ptr?.pointee else { continue }
                let name = String(cString: interface.ifa_name)
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == sa_family_t(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, 0, NI_NUMERICHOST)
                    let ip = String(cString: hostname)
                    if name == "en0" {
                        freeifaddrs(ifaddr)
                        return ip
                    }
                    if name != "lo0" && address == nil {
                        address = ip
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }
    
    static func resolveBonjour() -> String? {
        print("[Discovery] Scanning local network using Bonjour (mDNS) for Pihu Display...")
        let resolver = BonjourResolver()
        return resolver.resolve(timeout: 4.0)
    }
    
    static func resolveAddress(mode: ConnectionMode, manualHost: String?) -> String? {
        switch mode {
        case .usb:
            return "127.0.0.1"
            
        case .wifi:
            if let manualHost = manualHost {
                print("[Discovery] Using manually specified host: \(manualHost)")
                return manualHost
            }
            
            // Tier 1: Gateway guess (hotspot)
            if let gatewayIP = getGatewayIP() {
                print("[Discovery] Tier 1: Detected default gateway IP (phone hotspot): \(gatewayIP)")
                // Quick connectivity check (e.g. check if we can open a socket)
                if testConnection(host: gatewayIP, port: 27183) {
                    print("[Discovery] Tier 1: Connection to gateway IP successful!")
                    return gatewayIP
                } else {
                    print("[Discovery] Tier 1: Gateway IP \(gatewayIP) not reachable on port 27183.")
                }
            }
            
            // Tier 2: Bonjour/mDNS
            if let bonjourIP = resolveBonjour() {
                print("[Discovery] Tier 2: Found Pihu Display via Bonjour: \(bonjourIP)")
                return bonjourIP
            }
            
            return nil
            
        case .auto:
            // Check if adb device is connected by running adb devices command
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            // Search in typical paths: /opt/homebrew/bin/adb, /usr/local/bin/adb, or path
            process.arguments = ["-c", "which adb > /dev/null && adb devices | grep -v 'List' | grep 'device' | wc -l || echo '0'"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            var adbDevicesCount = 0
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8),
                   let count = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    adbDevicesCount = count
                }
            } catch {
                // Ignore errors, default to 0
            }
            
            if adbDevicesCount > 0 {
                print("[Discovery] Auto-detected connected ADB USB device. Defaulting to USB mode.")
                return "127.0.0.1"
            }
            
            print("[Discovery] No USB device detected. Attempting Wi-Fi mode discovery...")
            return resolveAddress(mode: .wifi, manualHost: manualHost)
        }
    }
    
    private static func testConnection(host: String, port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        
        // Set non-blocking to allow timeout
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)
        
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
            return true
        }
        
        if errno == EINPROGRESS {
            var writefds = fd_set()
            writefds.fds_bits.0 = 1 << sock
            
            var timeout = timeval()
            timeout.tv_sec = 0
            timeout.tv_usec = 500_000 // 500ms timeout
            
            let selectResult = select(sock + 1, nil, &writefds, nil, &timeout)
            if selectResult > 0 {
                var err: Int32 = 0
                var len = socklen_t(MemoryLayout<Int32>.size)
                let status = getsockopt(sock, SOL_SOCKET, SO_ERROR, &err, &len)
                return status == 0 && err == 0
            }
        }
        
        return false
    }
}

class BonjourResolver: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var resolvedIP: String?
    private var activeService: NetService?
    private var isDone = false
    
    func resolve(timeout: TimeInterval = 4.0) -> String? {
        let thread = Thread { [weak self] in
            guard let self = self else { return }
            
            self.browser.delegate = self
            self.browser.searchForServices(ofType: "_pihu._tcp.", inDomain: "local.")
            
            let limitDate = Date(timeIntervalSinceNow: timeout)
            while !self.isDone && RunLoop.current.run(mode: .default, before: limitDate) {
                if Date() > limitDate {
                    break
                }
            }
            
            self.browser.stop()
            self.activeService?.stop()
        }
        
        thread.start()
        
        while !thread.isFinished {
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        return resolvedIP
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        activeService = service
        service.delegate = self
        service.resolve(withTimeout: 2.0)
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses else { return }
        for address in addresses {
            address.withUnsafeBytes { ptr in
                guard ptr.count >= MemoryLayout<sockaddr>.size else { return }
                let sockaddrPtr = ptr.baseAddress!.assumingMemoryBound(to: sockaddr.self)
                if sockaddrPtr.pointee.sa_family == sa_family_t(AF_INET) {
                    let sockaddrInPtr = ptr.baseAddress!.assumingMemoryBound(to: sockaddr_in.self)
                    var sinAddr = sockaddrInPtr.pointee.sin_addr
                    var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    inet_ntop(AF_INET, &sinAddr, &ipBuffer, socklen_t(INET_ADDRSTRLEN))
                    let ipString = String(cString: ipBuffer)
                    if !ipString.isEmpty {
                        resolvedIP = ipString
                        isDone = true
                    }
                }
            }
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        isDone = true
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        isDone = true
    }
}
