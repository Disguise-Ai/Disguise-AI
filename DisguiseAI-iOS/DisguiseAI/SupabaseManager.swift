import Foundation

class SupabaseManager {
    static let shared = SupabaseManager()

    // Read from Config.json
    private var supabaseURL: String { ConfigManager.shared.supabaseURL }
    private var supabaseAnonKey: String { ConfigManager.shared.supabaseAnonKey }

    private init() {}

    // MARK: - Sign Up with Email/Password
    func signUp(email: String, password: String, completion: @escaping (Result<SupabaseUser, Error>) -> Void) {
        guard let url = URL(string: "\(supabaseURL)/auth/v1/signup") else {
            completion(.failure(SupabaseError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "email": email,
            "password": password
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
                    completion(.failure(SupabaseError.serverError("couldn't connect")))
                    return
                }

                guard let data = data else {
                    completion(.failure(SupabaseError.noData))
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Check for error responses
                        if let errorMsg = json["error_description"] as? String {
                            completion(.failure(SupabaseError.serverError(errorMsg)))
                            return
                        }
                        if let errorMsg = json["msg"] as? String {
                            completion(.failure(SupabaseError.serverError(errorMsg)))
                            return
                        }
                        if let errorMsg = json["error"] as? String, let code = json["error_code"] as? String {
                            completion(.failure(SupabaseError.serverError("\(errorMsg) (\(code))")))
                            return
                        }
                        if let message = json["message"] as? String, json["user"] == nil && json["id"] == nil {
                            completion(.failure(SupabaseError.serverError(message)))
                            return
                        }

                        // Try to get user ID from nested "user" object first
                        if let userJson = json["user"] as? [String: Any],
                           let userId = userJson["id"] as? String {
                            let userEmail = userJson["email"] as? String ?? email
                            let user = SupabaseUser(id: userId, email: userEmail)

                            // Save access token if present
                            if let accessToken = json["access_token"] as? String {
                                UserDefaults.standard.set(accessToken, forKey: "supabase_access_token")
                            }

                            completion(.success(user))
                            return
                        }

                        // Try root level "id" (when email confirmation is required)
                        if let userId = json["id"] as? String {
                            let userEmail = json["email"] as? String ?? email
                            let user = SupabaseUser(id: userId, email: userEmail)
                            completion(.success(user))
                            return
                        }

                        // Check if identities array exists (another Supabase response format)
                        if let identities = json["identities"] as? [[String: Any]],
                           let firstIdentity = identities.first,
                           let userId = firstIdentity["user_id"] as? String {
                            let user = SupabaseUser(id: userId, email: email)
                            completion(.success(user))
                            return
                        }

                        // Debug: print what we got
                        print("Supabase signup response: \(json)")
                        completion(.failure(SupabaseError.serverError("unexpected response format")))
                    } else {
                        completion(.failure(SupabaseError.invalidResponse))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Sign In with Email/Password
    func signIn(email: String, password: String, completion: @escaping (Result<SupabaseUser, Error>) -> Void) {
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=password") else {
            completion(.failure(SupabaseError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "email": email,
            "password": password
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
                    completion(.failure(SupabaseError.serverError("couldn't connect")))
                    return
                }

                guard let data = data else {
                    completion(.failure(SupabaseError.noData))
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Check for error
                        if let errorMsg = json["error_description"] as? String ?? json["msg"] as? String ?? json["error"] as? String {
                            completion(.failure(SupabaseError.serverError(errorMsg)))
                            return
                        }

                        // Parse user data
                        if let userJson = json["user"] as? [String: Any],
                           let userId = userJson["id"] as? String {
                            let userEmail = userJson["email"] as? String ?? email
                            let user = SupabaseUser(id: userId, email: userEmail)

                            // Save access token
                            if let accessToken = json["access_token"] as? String {
                                UserDefaults.standard.set(accessToken, forKey: "supabase_access_token")
                            }

                            completion(.success(user))
                        } else {
                            completion(.failure(SupabaseError.serverError("invalid email or password")))
                        }
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Save user profile (via Supabase REST API)
    func saveUserProfile(userId: String, email: String?, name: String?, vibes: [String], completion: @escaping (Result<Bool, Error>) -> Void) {
        // Use upsert to create or update profile
        guard let url = URL(string: "\(supabaseURL)/rest/v1/profiles") else {
            completion(.failure(SupabaseError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")  // Upsert
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "id": userId,
            "email": email ?? "",
            "name": name ?? "",
            "personality": vibes
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

                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    completion(.success(true))
                } else {
                    // Don't fail - profile saving is not critical
                    completion(.success(true))
                }
            }
        }.resume()
    }

    // MARK: - Update user settings (via Supabase REST API)
    func updateUserSettings(userId: String, settings: [String: Any], completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/profiles?id=eq.\(userId)") else {
            completion(.failure(SupabaseError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: settings)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    completion(.success(true))
                } else {
                    // Don't fail - settings update is not critical
                    completion(.success(true))
                }
            }
        }.resume()
    }

    // MARK: - Fetch user profile (on sign in via Supabase REST API)
    func fetchUserProfile(userId: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/profiles?id=eq.\(userId)&select=*") else {
            completion(.failure(SupabaseError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(SupabaseError.noData))
                    return
                }

                do {
                    // Supabase REST returns an array
                    if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                       let profile = jsonArray.first {
                        completion(.success(profile))
                    } else {
                        // No profile found - not an error, just empty
                        completion(.success([:]))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}

// MARK: - Models
struct SupabaseUser {
    let id: String
    let email: String
}

enum SupabaseError: LocalizedError {
    case invalidURL
    case noData
    case invalidResponse
    case notAuthenticated
    case serverError(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .noData: return "No data received"
        case .invalidResponse: return "Invalid response"
        case .notAuthenticated: return "Not authenticated"
        case .serverError(let msg): return msg
        case .unknown: return "Unknown error"
        }
    }
}
