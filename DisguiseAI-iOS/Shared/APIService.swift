import Foundation
import UIKit

// Shared API service using Supabase Edge Functions
class APIService {
    static let shared = APIService()

    // Supabase Edge Function URLs
    private var supabaseURL: String { ConfigManager.shared.supabaseURL }
    private var supabaseAnonKey: String { ConfigManager.shared.supabaseAnonKey }

    private var chatFunctionURL: String { "\(supabaseURL)/functions/v1/chat" }
    private var analyzeImageFunctionURL: String { "\(supabaseURL)/functions/v1/analyze-image" }

    private init() {}

    // MARK: - Send Message (Chat) via Supabase Edge Function
    func sendMessage(_ message: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: chatFunctionURL) else {
            completion(.failure(APIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        // Check if user is on trial (not premium)
        let isTrialUser = !SharedDefaults.shared.isPremium

        let body: [String: Any] = [
            "message": message,
            "userId": SharedDefaults.shared.userId ?? "anonymous",
            "responseStyle": SharedDefaults.shared.responseStyle,
            "isTrialUser": isTrialUser,
            "userName": SharedDefaults.shared.userName ?? "",
            "personality": SharedDefaults.shared.personality,
            "textSamples": SharedDefaults.shared.textSamples
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

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
                    } else {
                        completion(.failure(APIError.invalidResponse))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Send Image with Context via Supabase Edge Function
    func sendImageWithContext(_ image: UIImage, who: String, help: String, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                DispatchQueue.main.async { completion(.failure(APIError.invalidResponse)) }
                return
            }

            let base64Image = imageData.base64EncodedString()

            guard let url = URL(string: self.analyzeImageFunctionURL) else {
                DispatchQueue.main.async { completion(.failure(APIError.invalidURL)) }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(self.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 60

            let isTrialUser = !SharedDefaults.shared.isPremium

            let body: [String: Any] = [
                "imageBase64": base64Image,
                "contextWho": who,
                "contextHelp": help,
                "isTrialUser": isTrialUser,
                "userName": SharedDefaults.shared.userName ?? "",
                "textSamples": SharedDefaults.shared.textSamples
            ]

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

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

    // MARK: - Send Image (Chat) - wrapper for compatibility
    func sendImage(_ image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        sendImageWithContext(image, who: "", help: "", completion: completion)
    }

    // MARK: - Get AI Suggestions (Keyboard)
    func getSuggestions(
        context: String,
        userId: String,
        conversationType: String = "dating",
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard let url = URL(string: chatFunctionURL) else {
            completion(.failure(APIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let isTrialUser = !SharedDefaults.shared.isPremium

        let body: [String: Any] = [
            "message": "Give me 3 short reply suggestions for this conversation context: \(context)",
            "userId": userId,
            "isTrialUser": isTrialUser,
            "userName": SharedDefaults.shared.userName ?? "",
            "personality": SharedDefaults.shared.personality,
            "textSamples": SharedDefaults.shared.textSamples
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

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
                        // Parse suggestions from reply
                        let suggestions = self.parseSuggestions(from: reply)
                        completion(.success(suggestions))
                    } else {
                        completion(.failure(APIError.invalidResponse))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Analyze Screenshot (Keyboard)
    func analyzeScreenshot(
        imageData: Data,
        userId: String,
        goal: String = "respond",
        contextWho: String = "",
        contextHelp: String = "",
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        let base64Image = imageData.base64EncodedString()

        guard let url = URL(string: analyzeImageFunctionURL) else {
            completion(.failure(APIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let isTrialUser = !SharedDefaults.shared.isPremium

        let body: [String: Any] = [
            "imageBase64": base64Image,
            "contextWho": contextWho,
            "contextHelp": contextHelp,
            "isTrialUser": isTrialUser,
            "userName": SharedDefaults.shared.userName ?? "",
            "textSamples": SharedDefaults.shared.textSamples
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

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
                        let suggestions = self.parseSuggestions(from: reply)
                        completion(.success(suggestions))
                    } else {
                        completion(.failure(APIError.invalidResponse))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Helper to parse suggestions from AI reply
    private func parseSuggestions(from text: String) -> [String] {
        // Try to extract quoted suggestions
        let pattern = "\"([^\"]{5,100})\""
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)

            let suggestions = matches.compactMap { match -> String? in
                if let range = Range(match.range(at: 1), in: text) {
                    return String(text[range])
                }
                return nil
            }.filter { !$0.lowercased().contains("their message") && !$0.lowercased().contains("suggestion") }

            if suggestions.count >= 2 {
                return Array(suggestions.prefix(3))
            }
        }

        // Fallback: split by newlines and clean up
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 5 && $0.count < 100 }
            .filter { !$0.lowercased().contains("here") && !$0.lowercased().contains("option") }

        if lines.count >= 2 {
            return Array(lines.prefix(3))
        }

        // Final fallback
        return ["hey what's up", "that's cool", "tell me more"]
    }

    // MARK: - Get/Save User Profile (using Supabase direct)
    func getProfile(userId: String, completion: @escaping (Result<UserProfile, Error>) -> Void) {
        // Use Supabase REST API to get profile
        guard let url = URL(string: "\(supabaseURL)/rest/v1/profiles?id=eq.\(userId)&select=*") else {
            completion(.failure(APIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")

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
                    let profiles = try JSONDecoder().decode([UserProfile].self, from: data)
                    if let profile = profiles.first {
                        completion(.success(profile))
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

// MARK: - Models
struct UserProfile: Codable {
    let id: String
    let name: String?
    let answers: [String]?
    let textSamples: String?
    let style: StylePreferences?
    let who: [String]?
    let struggles: [String]?
    let personality: [String]?
    let about: String?

    enum CodingKeys: String, CodingKey {
        case id, name, answers, textSamples = "text_samples", style, who, struggles, personality, about
    }
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
