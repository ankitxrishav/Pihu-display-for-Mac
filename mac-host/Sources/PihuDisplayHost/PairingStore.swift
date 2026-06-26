import Foundation

class PairingStore {
    static let shared = PairingStore()
    
    private let fileManager = FileManager.default
    private let appSupportURL: URL
    private let settingsURL: URL
    
    private var clientID: String = ""
    private var devices: [String: String] = [:]
    
    private struct StorageModel: Codable {
        let clientID: String
        let devices: [String: String]
    }
    
    private init() {
        // Resolve app support directory path
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("PihuDisplay")
        self.appSupportURL = appSupport
        self.settingsURL = appSupport.appendingPathComponent("paired.json")
        
        load()
    }
    
    func getClientID() -> String {
        return clientID
    }
    
    func getToken(forDevice deviceName: String) -> String? {
        return devices[deviceName]
    }
    
    func saveToken(_ token: String, forDevice deviceName: String) {
        devices[deviceName] = token
        save()
    }
    
    private func load() {
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Try reading from paired.json
        if fileManager.fileExists(atPath: settingsURL.path),
           let data = try? Data(contentsOf: settingsURL),
           let model = try? JSONDecoder().decode(StorageModel.self, from: data) {
            self.clientID = model.clientID
            self.devices = model.devices
            print("[PairingStore] Loaded clientID: \(self.clientID), devices count: \(self.devices.count)")
        } else {
            // Generate a new client ID
            self.clientID = UUID().uuidString
            self.devices = [:]
            save()
            print("[PairingStore] Generated new clientID: \(self.clientID)")
        }
    }
    
    private func save() {
        let model = StorageModel(clientID: clientID, devices: devices)
        if let data = try? JSONEncoder().encode(model) {
            do {
                try data.write(to: settingsURL)
            } catch {
                print("[PairingStore] Failed to write settings to \(settingsURL.path): \(error)")
            }
        }
    }
}
