import Foundation

// Reads configuration from Config.json
class ConfigManager {
    static let shared = ConfigManager()

    private var config: [String: Any] = [:]

    private init() {
        loadConfig()
    }

    private func loadConfig() {
        // Try to load from main bundle first, then from shared location
        if let url = Bundle.main.url(forResource: "Config", withExtension: "json") {
            loadFromURL(url)
        } else if let url = Bundle.main.url(forResource: "Config", withExtension: "json", subdirectory: "Shared") {
            loadFromURL(url)
        }
    }

    private func loadFromURL(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                config = json
            }
        } catch {
            print("ConfigManager: Failed to load config: \(error)")
        }
    }

    // MARK: - Supabase
    var supabaseURL: String {
        if let supabase = config["supabase"] as? [String: Any],
           let url = supabase["url"] as? String {
            return url
        }
        return "https://ppnswzypkrqztgcluoin.supabase.co"
    }

    var supabaseAnonKey: String {
        if let supabase = config["supabase"] as? [String: Any],
           let key = supabase["anonKey"] as? String {
            return key
        }
        return ""
    }

    // MARK: - Server
    var serverBaseURL: String {
        if let server = config["server"] as? [String: Any],
           let url = server["baseURL"] as? String {
            return url
        }
        return "http://192.168.1.64:3000"
    }

    // MARK: - App Group
    var appGroup: String {
        if let group = config["appGroup"] as? String {
            return group
        }
        return "group.com.rashaadjackson.disguiseai"
    }
}
