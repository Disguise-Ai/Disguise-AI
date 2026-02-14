import Foundation

// Shared UserDefaults for communication between main app and extensions
// Uses App Group to share data, falls back to standard UserDefaults if not available
class SharedDefaults {
    static let shared = SharedDefaults()

    // Read from Config.json
    private var suiteName: String { ConfigManager.shared.appGroup }

    private var defaults: UserDefaults {
        // Try App Group first, fall back to standard UserDefaults
        if let groupDefaults = UserDefaults(suiteName: suiteName) {
            return groupDefaults
        }
        return UserDefaults.standard
    }

    private init() {}

    // MARK: - User ID
    var userId: String? {
        get { defaults.string(forKey: "userId") }
        set { defaults.set(newValue, forKey: "userId") }
    }

    // MARK: - User Name
    var userName: String? {
        get { defaults.string(forKey: "userName") }
        set { defaults.set(newValue, forKey: "userName") }
    }

    // MARK: - Phone Verification
    var hasVerifiedPhone: Bool {
        get { defaults.bool(forKey: "hasVerifiedPhone") }
        set { defaults.set(newValue, forKey: "hasVerifiedPhone") }
    }

    var phoneNumber: String? {
        get { defaults.string(forKey: "phoneNumber") }
        set { defaults.set(newValue, forKey: "phoneNumber") }
    }

    var supabaseUserId: String? {
        get { defaults.string(forKey: "supabaseUserId") }
        set { defaults.set(newValue, forKey: "supabaseUserId") }
    }

    // MARK: - Onboarding Complete
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    // MARK: - Keyboard Setup Complete
    var hasCompletedKeyboardSetup: Bool {
        get { defaults.bool(forKey: "hasCompletedKeyboardSetup") }
        set { defaults.set(newValue, forKey: "hasCompletedKeyboardSetup") }
    }

    // MARK: - Style Preferences
    var responseStyle: String {
        get { defaults.string(forKey: "responseStyle") ?? "normal" }
        set { defaults.set(newValue, forKey: "responseStyle") }
    }

    var messageLength: String {
        get { defaults.string(forKey: "messageLength") ?? "2" }
        set { defaults.set(newValue, forKey: "messageLength") }
    }

    var emojiUsage: String {
        get { defaults.string(forKey: "emojiUsage") ?? "2" }
        set { defaults.set(newValue, forKey: "emojiUsage") }
    }

    var flirtiness: String {
        get { defaults.string(forKey: "flirtiness") ?? "1" }
        set { defaults.set(newValue, forKey: "flirtiness") }
    }

    // MARK: - Vibe/Personality
    var selectedVibes: [String] {
        get { defaults.stringArray(forKey: "selectedVibes") ?? [] }
        set { defaults.set(newValue, forKey: "selectedVibes") }
    }

    var personality: [String] {
        get { defaults.stringArray(forKey: "personality") ?? [] }
        set { defaults.set(newValue, forKey: "personality") }
    }

    // MARK: - Text Samples
    var textSamples: String {
        get { defaults.string(forKey: "textSamples") ?? "" }
        set { defaults.set(newValue, forKey: "textSamples") }
    }

    // MARK: - Recent Suggestions (for quick access)
    var recentSuggestions: [String] {
        get { defaults.stringArray(forKey: "recentSuggestions") ?? [] }
        set {
            // Keep only last 10
            let trimmed = Array(newValue.prefix(10))
            defaults.set(trimmed, forKey: "recentSuggestions")
        }
    }

    // MARK: - Clipboard Context (from share extension)
    var pendingContext: String? {
        get { defaults.string(forKey: "pendingContext") }
        set { defaults.set(newValue, forKey: "pendingContext") }
    }

    // MARK: - Pending Suggestion (auto-copied from share extension)
    var pendingSuggestion: String? {
        get { defaults.string(forKey: "pendingSuggestion") }
        set { defaults.set(newValue, forKey: "pendingSuggestion") }
    }

    // MARK: - Local Chat History (for instant loading)
    var localChatHistory: [[String: Any]] {
        get {
            guard let data = defaults.data(forKey: "localChatHistory"),
                  let history = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            return history
        }
        set {
            // Keep last 100 messages
            let trimmed = Array(newValue.suffix(100))
            if let data = try? JSONSerialization.data(withJSONObject: trimmed) {
                defaults.set(data, forKey: "localChatHistory")
            }
        }
    }

    func appendChatMessage(text: String, isUser: Bool) {
        var history = localChatHistory
        history.append(["text": text, "isUser": isUser, "timestamp": Date().timeIntervalSince1970])
        localChatHistory = history
    }

    func clearChatHistory() {
        defaults.removeObject(forKey: "localChatHistory")
    }

    // MARK: - Conversation History (multiple conversations)
    var savedConversations: [[String: Any]] {
        get {
            guard let data = defaults.data(forKey: "savedConversations"),
                  let convos = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            return convos
        }
        set {
            // Keep last 20 conversations
            let trimmed = Array(newValue.suffix(20))
            if let data = try? JSONSerialization.data(withJSONObject: trimmed) {
                defaults.set(data, forKey: "savedConversations")
            }
        }
    }

    func saveCurrentConversation() {
        let currentHistory = localChatHistory
        guard !currentHistory.isEmpty else { return }

        // Create conversation object
        let conversation: [String: Any] = [
            "id": UUID().uuidString,
            "messages": currentHistory,
            "createdAt": Date().timeIntervalSince1970,
            "preview": (currentHistory.first?["text"] as? String) ?? "Conversation"
        ]

        var convos = savedConversations
        convos.insert(conversation, at: 0)  // Add to beginning (newest first)
        savedConversations = convos
    }

    func deleteConversation(id: String) {
        var convos = savedConversations
        convos.removeAll { ($0["id"] as? String) == id }
        savedConversations = convos
    }

    func clearAllConversations() {
        defaults.removeObject(forKey: "savedConversations")
    }

    // MARK: - Verified User (completed auth + has profile)
    var isVerifiedUser: Bool {
        get { defaults.bool(forKey: "isVerifiedUser") }
        set { defaults.set(newValue, forKey: "isVerifiedUser") }
    }

    // MARK: - Trial & Premium
    var trialStartDate: Date? {
        get { defaults.object(forKey: "trialStartDate") as? Date }
        set { defaults.set(newValue, forKey: "trialStartDate") }
    }

    var isPremium: Bool {
        get { defaults.bool(forKey: "isPremium") }
        set { defaults.set(newValue, forKey: "isPremium") }
    }

    var isTrialExpired: Bool {
        if isPremium { return false }
        guard let startDate = trialStartDate else { return false }
        let daysSinceStart = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        return daysSinceStart >= 7
    }

    var trialDaysRemaining: Int {
        if isPremium { return 0 }
        guard let startDate = trialStartDate else { return 7 }
        let daysSinceStart = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        return max(0, 7 - daysSinceStart)
    }

    // MARK: - Trial Photo Limit
    var trialPhotoUploads: Int {
        get { defaults.integer(forKey: "trialPhotoUploads") }
        set { defaults.set(newValue, forKey: "trialPhotoUploads") }
    }

    var canUploadPhoto: Bool {
        if isPremium { return true }
        return trialPhotoUploads < 5  // Allow 5 photo uploads for trial users
    }

    var trialPhotosRemaining: Int {
        if isPremium { return 999 }
        return max(0, 5 - trialPhotoUploads)  // 5 photos for trial
    }

    // MARK: - Clear All
    func clearAll() {
        let keys = ["userId", "userName", "hasVerifiedPhone", "phoneNumber", "supabaseUserId",
                    "hasCompletedOnboarding", "hasCompletedKeyboardSetup",
                    "responseStyle", "messageLength", "emojiUsage", "flirtiness", "selectedVibes",
                    "personality", "textSamples", "recentSuggestions", "pendingContext",
                    "pendingSuggestion", "trialStartDate", "isPremium", "localChatHistory",
                    "isVerifiedUser", "savedConversations", "trialPhotoUploads"]
        keys.forEach { defaults.removeObject(forKey: $0) }
    }
}
