import Foundation
import UIKit

// Shared API service used by main app, keyboard, and share extension
class APIService {
    static let shared = APIService()

    // Read from Config.json
    private var baseURL: String { ConfigManager.shared.serverBaseURL }

    private init() {}

    // MARK: - Get AI Suggestions
    func getSuggestions(
        context: String,
        userId: String,
        conversationType: String = "dating",
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/api/keyboard/suggest") else {
            completion(.failure(APIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "context": context,
            "userId": userId,
            "conversationType": conversationType
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let suggestions = json["suggestions"] as? [String] {
                    completion(.success(suggestions))
                } else {
                    completion(.failure(APIError.invalidResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Analyze Screenshot
    func analyzeScreenshot(
        imageData: Data,
        userId: String,
        goal: String = "respond",
        contextWho: String = "",
        contextHelp: String = "",
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/api/keyboard/analyze-image") else {
            completion(.failure(APIError.invalidURL))
            return
        }

        // Unique filename with timestamp to prevent any caching
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let uniqueFilename = "keyboard_\(timestamp).jpg"

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // Disable caching
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30

        var body = Data()

        // Add image with unique filename
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(uniqueFilename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        // Add userId
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"userId\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(userId)\r\n".data(using: .utf8)!)

        // Add goal
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"goal\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(goal)\r\n".data(using: .utf8)!)

        // Add context: who they're texting
        if !contextWho.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"contextWho\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(contextWho)\r\n".data(using: .utf8)!)
        }

        // Add context: what help they need
        if !contextHelp.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"contextHelp\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(contextHelp)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let suggestions = json["suggestions"] as? [String] {
                    completion(.success(suggestions))
                } else {
                    completion(.failure(APIError.invalidResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Send Message (Chat)
    func sendMessage(_ message: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/message") else {
            completion(.failure(APIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let userId = SharedDefaults.shared.userId ?? "anonymous"
        let responseStyle = SharedDefaults.shared.responseStyle
        let msgLength = SharedDefaults.shared.messageLength
        let emojiUsage = SharedDefaults.shared.emojiUsage
        let flirtiness = SharedDefaults.shared.flirtiness
        let textSamples = SharedDefaults.shared.textSamples

        // Check if user is on trial (not premium)
        let isTrialUser = !SharedDefaults.shared.isPremium

        let body: [String: Any] = [
            "message": message,
            "userId": userId,
            "responseStyle": responseStyle,
            "msgLength": msgLength,
            "emojiUsage": emojiUsage,
            "flirtiness": flirtiness,
            "userSamples": textSamples,
            "isTrialUser": isTrialUser ? "true" : "false"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let reply = json["reply"] as? String {
                    completion(.success(reply))
                } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let response = json["response"] as? String {
                    completion(.success(response))
                } else {
                    completion(.failure(APIError.invalidResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Send Image (Chat)
    func sendImage(_ image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.75) else {
            completion(.failure(APIError.invalidResponse))
            return
        }

        guard let url = URL(string: "\(baseURL)/api/message") else {
            completion(.failure(APIError.invalidURL))
            return
        }

        // Unique filename with timestamp
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let uniqueFilename = "image_\(timestamp).jpg"

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 60

        let userId = SharedDefaults.shared.userId ?? "anonymous"
        let responseStyle = SharedDefaults.shared.responseStyle
        let msgLength = SharedDefaults.shared.messageLength
        let emojiUsage = SharedDefaults.shared.emojiUsage
        let flirtiness = SharedDefaults.shared.flirtiness

        var body = Data()

        // Add image with unique filename
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(uniqueFilename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        // Add userId
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"userId\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(userId)\r\n".data(using: .utf8)!)

        // Add responseStyle
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"responseStyle\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(responseStyle)\r\n".data(using: .utf8)!)

        // Add msgLength
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"msgLength\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(msgLength)\r\n".data(using: .utf8)!)

        // Add emojiUsage
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"emojiUsage\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(emojiUsage)\r\n".data(using: .utf8)!)

        // Add flirtiness
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"flirtiness\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(flirtiness)\r\n".data(using: .utf8)!)

        // Add isTrialUser flag
        let isTrialUser = !SharedDefaults.shared.isPremium
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"isTrialUser\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(isTrialUser ? "true" : "false")\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let reply = json["reply"] as? String {
                    completion(.success(reply))
                } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let response = json["response"] as? String {
                    completion(.success(response))
                } else {
                    completion(.failure(APIError.invalidResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Send Image with Context (Chat)
    func sendImageWithContext(_ image: UIImage, who: String, help: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Compress on background thread for speed
        DispatchQueue.global(qos: .userInitiated).async {
            guard let imageData = image.jpegData(compressionQuality: 0.75) else {
                DispatchQueue.main.async { completion(.failure(APIError.invalidResponse)) }
                return
            }

            guard let url = URL(string: "\(self.baseURL)/api/message") else {
                DispatchQueue.main.async { completion(.failure(APIError.invalidURL)) }
                return
            }

            // Unique filename with timestamp to prevent any caching
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let uniqueFilename = "screenshot_\(timestamp).jpg"

            let boundary = UUID().uuidString
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            // Disable caching
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 20

            let userId = SharedDefaults.shared.userId ?? "anonymous"
            let responseStyle = SharedDefaults.shared.responseStyle
            let msgLength = SharedDefaults.shared.messageLength
            let emojiUsage = SharedDefaults.shared.emojiUsage
            let flirtiness = SharedDefaults.shared.flirtiness

            var body = Data()

            // Add image with unique filename
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(uniqueFilename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)

        // Add userId
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"userId\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(userId)\r\n".data(using: .utf8)!)

        // Add context: who they're texting
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"contextWho\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(who)\r\n".data(using: .utf8)!)

        // Add context: what help they need
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"contextHelp\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(help)\r\n".data(using: .utf8)!)

        // Add responseStyle
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"responseStyle\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(responseStyle)\r\n".data(using: .utf8)!)

        // Add msgLength
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"msgLength\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(msgLength)\r\n".data(using: .utf8)!)

        // Add emojiUsage
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"emojiUsage\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(emojiUsage)\r\n".data(using: .utf8)!)

        // Add flirtiness
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"flirtiness\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(flirtiness)\r\n".data(using: .utf8)!)

        // Add isTrialUser flag
        let isTrialUser = !SharedDefaults.shared.isPremium
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"isTrialUser\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(isTrialUser ? "true" : "false")\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    guard let data = data else {
                        completion(.failure(APIError.noData))
                        return
                    }

                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let reply = json["reply"] as? String {
                            completion(.success(reply))
                        } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                                  let response = json["response"] as? String {
                            completion(.success(response))
                        } else {
                            completion(.failure(APIError.invalidResponse))
                        }
                    } catch {
                        completion(.failure(error))
                    }
                }
            }.resume()
        }
    }

    // MARK: - Get/Save User Profile
    func getProfile(userId: String, completion: @escaping (Result<UserProfile, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/profile/\(userId)") else {
            completion(.failure(APIError.invalidURL))
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }

            do {
                let profile = try JSONDecoder().decode(UserProfile.self, from: data)
                completion(.success(profile))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

// MARK: - Models
struct UserProfile: Codable {
    let id: String
    let name: String?
    let answers: [String]
    let textSamples: String?
    let style: StylePreferences?
    let who: [String]?
    let struggles: [String]?
    let personality: [String]?
    let about: String?
}

struct StylePreferences: Codable {
    let length: String?
    let emoji: String?
    let flirt: String?
}

enum APIError: Error {
    case invalidURL
    case noData
    case invalidResponse
}
