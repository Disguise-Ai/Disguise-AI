import SwiftUI
import UIKit
import Photos

struct ContentView: View {
    // Load state immediately from SharedDefaults (synchronous, no lag)
    @State private var hasVerifiedPhone = SharedDefaults.shared.hasVerifiedPhone
    @State private var hasCompletedOnboarding = SharedDefaults.shared.hasCompletedOnboarding
    @State private var hasCompletedKeyboardSetup = SharedDefaults.shared.hasCompletedKeyboardSetup

    var body: some View {
        Group {
            if !hasVerifiedPhone {
                EmailAuthView(onComplete: {
                    SharedDefaults.shared.hasVerifiedPhone = true
                    hasVerifiedPhone = true
                    // For returning users, also update local state from SharedDefaults
                    hasCompletedOnboarding = SharedDefaults.shared.hasCompletedOnboarding
                    hasCompletedKeyboardSetup = SharedDefaults.shared.hasCompletedKeyboardSetup
                })
            } else if !hasCompletedOnboarding {
                OnboardingView(onComplete: {
                    SharedDefaults.shared.hasCompletedOnboarding = true
                    hasCompletedOnboarding = true
                })
            } else if !hasCompletedKeyboardSetup {
                KeyboardSetupView(
                    onComplete: {
                        SharedDefaults.shared.hasCompletedKeyboardSetup = true
                        hasCompletedKeyboardSetup = true
                    },
                    onSkip: {
                        SharedDefaults.shared.hasCompletedKeyboardSetup = true
                        hasCompletedKeyboardSetup = true
                    }
                )
            } else {
                ChatView(onReset: {
                    SharedDefaults.shared.clearAll()
                    SharedDefaults.shared.clearChatHistory()
                    UserDefaults.standard.removeObject(forKey: "supabase_access_token")
                    hasVerifiedPhone = false
                    hasCompletedOnboarding = false
                    hasCompletedKeyboardSetup = false
                })
            }
        }
    }
}

// MARK: - Email Auth View
struct EmailAuthView: View {
    let onComplete: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = true  // Toggle between sign up and sign in
    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Text("Disguise")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.primary)
                    Text(".AI")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(.gray)
                }

                Text("your texting wingman")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 50)

            // Email/Password Input
            VStack(spacing: 16) {
                // Email input
                VStack(alignment: .leading, spacing: 8) {
                    Text("email")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField("you@email.com", text: $email)
                        .font(.system(size: 18))
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                }

                // Password input
                VStack(alignment: .leading, spacing: 8) {
                    Text("password")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)

                    SecureField("••••••••", text: $password)
                        .font(.system(size: 18))
                        .textContentType(isSignUp ? .newPassword : .password)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                }

                // Error message
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Continue button and toggle
            VStack(spacing: 16) {
                Button(action: authenticate) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    } else {
                        Text(isSignUp ? "create account" : "sign in")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    }
                }
                .background(isButtonEnabled ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color.gray.opacity(0.3))
                .cornerRadius(14)
                .disabled(!isButtonEnabled || isLoading)

                // Toggle sign up / sign in
                Button(action: {
                    withAnimation {
                        isSignUp.toggle()
                        errorMessage = ""
                    }
                }) {
                    Text(isSignUp ? "already have an account? sign in" : "need an account? sign up")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private var isButtonEnabled: Bool {
        let isValidEmail = email.contains("@") && email.contains(".")
        let isValidPassword = password.count >= 6
        return isValidEmail && isValidPassword
    }

    private func authenticate() {
        guard isButtonEnabled else { return }

        isLoading = true
        errorMessage = ""

        if isSignUp {
            SupabaseManager.shared.signUp(email: email, password: password) { result in
                switch result {
                case .success(let user):
                    SharedDefaults.shared.supabaseUserId = user.id
                    SharedDefaults.shared.userId = user.id
                    SharedDefaults.shared.trialStartDate = Date()  // Start 7-day trial
                    SharedDefaults.shared.isVerifiedUser = true     // Mark as verified
                    isLoading = false
                    onComplete()

                case .failure(let error):
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        } else {
            // Sign in - returning user, skip all onboarding
            SupabaseManager.shared.signIn(email: email, password: password) { result in
                switch result {
                case .success(let user):
                    SharedDefaults.shared.supabaseUserId = user.id
                    SharedDefaults.shared.userId = user.id

                    // Returning user - they already went through onboarding once
                    // Skip everything and go straight to chat
                    SharedDefaults.shared.isVerifiedUser = true
                    SharedDefaults.shared.hasCompletedOnboarding = true
                    SharedDefaults.shared.hasCompletedKeyboardSetup = true

                    isLoading = false
                    onComplete()  // Continue immediately - don't wait for profile!

                    // Load profile in background (fire and forget)
                    DispatchQueue.global(qos: .background).async {
                        SupabaseManager.shared.fetchUserProfile(userId: user.id) { profileResult in
                            if case .success(let profile) = profileResult {
                                DispatchQueue.main.async {
                                    // Restore their settings silently
                                    if let name = profile["name"] as? String, !name.isEmpty {
                                        SharedDefaults.shared.userName = name
                                    }
                                    if let vibes = profile["personality"] as? [String] {
                                        SharedDefaults.shared.selectedVibes = vibes
                                        SharedDefaults.shared.personality = vibes
                                    }
                                    if let style = profile["responseStyle"] as? String {
                                        SharedDefaults.shared.responseStyle = style
                                    }
                                    if let length = profile["messageLength"] as? Int {
                                        SharedDefaults.shared.messageLength = String(length)
                                    }
                                    if let emoji = profile["emojiUsage"] as? Int {
                                        SharedDefaults.shared.emojiUsage = String(emoji)
                                    }
                                    if let flirt = profile["flirtiness"] as? Int {
                                        SharedDefaults.shared.flirtiness = String(flirt)
                                    }
                                    if let samples = profile["textSamples"] as? String {
                                        SharedDefaults.shared.textSamples = samples
                                    }

                                    // Restore deep personality settings
                                    if let val = profile["noReplyThought"] as? String { UserDefaults.standard.set(val, forKey: "noReplyThought") }
                                    if let val = profile["whenYouLikeSomeone"] as? String { UserDefaults.standard.set(val, forKey: "whenYouLikeSomeone") }
                                    if let val = profile["whatKillsConvos"] as? String { UserDefaults.standard.set(val, forKey: "whatKillsConvos") }
                                    if let val = profile["quietConvoResponse"] as? String { UserDefaults.standard.set(val, forKey: "quietConvoResponse") }
                                    if let val = profile["biggestFear"] as? String { UserDefaults.standard.set(val, forKey: "biggestFear") }
                                    if let val = profile["howThingsEnd"] as? String { UserDefaults.standard.set(val, forKey: "howThingsEnd") }
                                    if let val = profile["confidenceLevel"] as? String { UserDefaults.standard.set(val, forKey: "confidenceLevel") }
                                    if let val = profile["whatYouWant"] as? String { UserDefaults.standard.set(val, forKey: "whatYouWant") }

                                    // Restore premium status
                                    if let isPremium = profile["isPremium"] as? Bool, isPremium {
                                        SharedDefaults.shared.isPremium = true
                                    }

                                    // Restore trial start date if exists
                                    if let trialStart = profile["trialStartDate"] as? String {
                                        let formatter = ISO8601DateFormatter()
                                        if let date = formatter.date(from: trialStart) {
                                            SharedDefaults.shared.trialStartDate = date
                                        }
                                    }
                                }
                            }
                        }
                    }

                case .failure(let error):
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Onboarding View
struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var userName = ""
    @State private var selectedVibes: Set<String> = []

    let vibeOptions = ["Confident", "Funny", "Flirty", "Chill", "Mysterious", "Bold", "Witty", "Charming", "Playful", "Direct"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Text("Disguise")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.primary)
                    Text(".AI")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.gray)
                }

                Text("Effortlessly start meaningful conversations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 60)
            .padding(.bottom, 40)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Info card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The more you share, the better I get")
                            .font(.headline)
                        Text("I'll learn your style and give you responses that actually sound like you")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)

                    // Name input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your name")
                            .font(.headline)
                        TextField("Enter your name", text: $userName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    // Vibe selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How do you want to come across?")
                            .font(.headline)
                        Text("Select all that apply")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                            ForEach(vibeOptions, id: \.self) { vibe in
                                VibeButton(
                                    title: vibe,
                                    isSelected: selectedVibes.contains(vibe),
                                    action: {
                                        if selectedVibes.contains(vibe) {
                                            selectedVibes.remove(vibe)
                                        } else {
                                            selectedVibes.insert(vibe)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Continue button
            VStack(spacing: 16) {
                Button(action: completeOnboarding) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .background(selectedVibes.isEmpty ? Color.gray : Color(red: 0.13, green: 0.77, blue: 0.37))
                .cornerRadius(12)
                .disabled(selectedVibes.isEmpty)
            }
            .padding()
        }
    }

    private func completeOnboarding() {
        guard !selectedVibes.isEmpty else { return }

        // Save locally FIRST (instant - no waiting)
        SharedDefaults.shared.userName = userName
        SharedDefaults.shared.selectedVibes = Array(selectedVibes)
        SharedDefaults.shared.personality = Array(selectedVibes)
        SharedDefaults.shared.hasCompletedOnboarding = true

        // Use Supabase user ID if available, otherwise generate one
        let userId = SharedDefaults.shared.supabaseUserId ?? UUID().uuidString.prefix(8).lowercased()
        SharedDefaults.shared.userId = String(userId)

        // Continue immediately - don't wait for server!
        onComplete()

        // Sync to server in background (fire and forget)
        DispatchQueue.global(qos: .background).async {
            SupabaseManager.shared.saveUserProfile(
                userId: String(userId),
                email: nil,
                name: userName.isEmpty ? nil : userName,
                vibes: Array(selectedVibes)
            ) { _ in }

            let settings: [String: Any] = [
                "hasCompletedOnboarding": true,
                "name": userName,
                "personality": Array(selectedVibes)
            ]
            SupabaseManager.shared.updateUserSettings(userId: String(userId), settings: settings) { _ in }
        }
    }
}

// MARK: - Keyboard Setup View
struct KeyboardSetupView: View {
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var isKeyboardEnabled = false
    @State private var hasPhotoAccess = false
    @State private var showKeyboardInstructions = false
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Text("Disguise")
                        .font(.system(size: 28, weight: .bold))
                    Text(".AI")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.gray)
                }

                if let name = SharedDefaults.shared.userName, !name.isEmpty {
                    Text("Hey \(name)!")
                        .font(.title2)
                }

                Text("Quick setup to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            Spacer()

            // Status indicators
            VStack(spacing: 12) {
                if hasPhotoAccess {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Photo access enabled!")
                            .foregroundColor(.green)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                }

                if isKeyboardEnabled {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Keyboard enabled!")
                            .foregroundColor(.green)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                }
            }

            // Instructions
            VStack(spacing: 16) {
                SetupStep(
                    number: "1",
                    icon: "photo.stack",
                    title: "Allow Photo Access",
                    description: "So the keyboard can read your screenshots",
                    isComplete: hasPhotoAccess,
                    buttonTitle: hasPhotoAccess ? nil : "Allow Photos",
                    action: requestPhotoAccess
                )

                SetupStep(
                    number: "2",
                    icon: "keyboard",
                    title: "Add Disguise Keyboard",
                    description: "Tap button below → Add New Keyboard → Disguise",
                    isComplete: isKeyboardEnabled,
                    buttonTitle: isKeyboardEnabled ? nil : "Add Keyboard",
                    action: { showKeyboardInstructions = true }
                )

                SetupStep(
                    number: "3",
                    icon: "hand.tap",
                    title: "Allow Full Access",
                    description: "Tap Disguise → Enable 'Allow Full Access'",
                    isComplete: false,
                    buttonTitle: nil,
                    action: nil
                )
            }
            .padding(.horizontal)

            Spacer()

            // Continue button
            VStack(spacing: 12) {
                if hasPhotoAccess && isKeyboardEnabled {
                    Button(action: onComplete) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("All Set! Let's Go")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(red: 0.13, green: 0.77, blue: 0.37))
                        .cornerRadius(12)
                    }
                } else {
                    Button(action: onComplete) {
                        Text("Continue Anyway")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }

                Button(action: onSkip) {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .onAppear {
            checkKeyboardEnabled()
            checkPhotoAccess()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                checkKeyboardEnabled()
                checkPhotoAccess()
            }
        }
        .sheet(isPresented: $showKeyboardInstructions) {
            KeyboardInstructionsSheet(onOpenSettings: openKeyboardSettings, onDismiss: {
                showKeyboardInstructions = false
            })
        }
    }

    private func checkKeyboardEnabled() {
        let keyboards = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String] ?? []
        let inputModes = UITextInputMode.activeInputModes
        let hasDisguiseKeyboard = keyboards.contains { $0.contains("DisguiseKeyboard") || $0.contains("disguiseai") } ||
                                  inputModes.contains { $0.value(forKey: "identifier") as? String ?? "" == "com.disguiseai.app.keyboard" }
        isKeyboardEnabled = hasDisguiseKeyboard
    }

    private func checkPhotoAccess() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        hasPhotoAccess = (status == .authorized || status == .limited)
    }

    private func requestPhotoAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                hasPhotoAccess = (status == .authorized || status == .limited)
            }
        }
    }

    private func openKeyboardSettings() {
        // Try multiple URL schemes to open keyboard settings
        let urls = [
            "App-prefs:General&path=Keyboard/KEYBOARDS",
            "App-Prefs:root=General&path=Keyboard/KEYBOARDS",
            "prefs:root=General&path=Keyboard/KEYBOARDS",
            UIApplication.openSettingsURLString
        ]

        for urlString in urls {
            if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }

        // Fallback to general settings
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Keyboard Instructions Sheet
struct KeyboardInstructionsSheet: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header image
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 60))
                    .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                    .padding(.top, 20)

                Text("Enable Disguise Keyboard")
                    .font(.system(size: 24, weight: .bold))

                // Step by step instructions
                VStack(alignment: .leading, spacing: 20) {
                    InstructionRow(number: "1", text: "Tap 'Open Settings' below")
                    InstructionRow(number: "2", text: "Tap 'Keyboards'")
                    InstructionRow(number: "3", text: "Tap 'Add New Keyboard...'")
                    InstructionRow(number: "4", text: "Find and tap 'Disguise'")
                    InstructionRow(number: "5", text: "Tap 'Disguise' again")
                    InstructionRow(number: "6", text: "Enable 'Allow Full Access'")
                }
                .padding(.horizontal, 24)

                Spacer()

                // Open Settings button
                Button(action: {
                    onOpenSettings()
                }) {
                    HStack {
                        Image(systemName: "gear")
                        Text("Open Settings")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(red: 0.0, green: 0.48, blue: 1.0))
                    .cornerRadius(14)
                }
                .padding(.horizontal, 24)

                Text("Come back here when you're done!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Instruction Row
struct InstructionRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.0, green: 0.48, blue: 1.0))
                    .frame(width: 28, height: 28)
                Text(number)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }

            Text(text)
                .font(.system(size: 16))
                .foregroundColor(.primary)

            Spacer()
        }
    }
}

// MARK: - Setup Step Component
struct SetupStep: View {
    let number: String
    let icon: String
    let title: String
    let description: String
    let isComplete: Bool
    let buttonTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Number/Check circle
            ZStack {
                Circle()
                    .fill(isComplete ? Color.green : Color(red: 0.0, green: 0.48, blue: 1.0))
                    .frame(width: 28, height: 28)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text(number)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isComplete ? .green : .primary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let buttonTitle = buttonTitle, let action = action {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.0, green: 0.48, blue: 1.0))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(isComplete ? Color.green.opacity(0.05) : Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Chat View
struct ChatView: View {
    let onReset: () -> Void

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var showSettings = false
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var conversationStep = 0  // 0=greeting, 1=asked Q1, 2=asked Q2, 3=ready for help
    @State private var hasLoadedHistory = false

    // Image context flow
    @State private var pendingImage: UIImage?  // Image waiting to be analyzed
    @State private var imageContextStep = 0    // 0=none, 1=asked who, 2=asked what help
    @State private var imageContextWho = ""    // Who they're texting
    @State private var imageContextHelp = ""   // What they need help with

    // Quick tap options
    @State private var showingOptions: [String] = []

    // Trial & Premium
    @State private var showPaywall = false
    @State private var isTrialExpired = false

    // Conversation history
    @State private var showHistory = false

    // Session persistence (5 minutes)
    @Environment(\.scenePhase) var scenePhase
    @State private var lastActiveTime: Date = Date()

    // Option choices
    private let whoOptions = ["a crush", "dating app", "an ex", "just talking"]
    private let helpOptions = ["how to respond", "start the convo", "what to say next", "keep it going"]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Messages - iMessage style
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }

                            if isLoading {
                                HStack {
                                    TypingIndicator()
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                                .id("typing")
                            }

                            // Bottom anchor for scrolling
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                    }
                    .background(Color(UIColor.systemBackground))
                    .onChange(of: messages.count) { _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: isLoading) { _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onAppear {
                        scrollToBottom(proxy: proxy)
                    }
                }

                // Quick tap options (when showing)
                if !showingOptions.isEmpty {
                    VStack(spacing: 0) {
                        // Question header
                        Text(imageContextStep == 1 ? "who is this?" : "what do you need?")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.top, 14)
                            .padding(.bottom, 10)

                        // Options in a clean grid
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(showingOptions, id: \.self) { option in
                                Button(action: { optionTapped(option) }) {
                                    Text(option)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color(UIColor.secondarySystemBackground))
                                        .cornerRadius(10)
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .background(Color(UIColor.systemBackground))
                }

                // Input area - iMessage style (hidden when options showing)
                if showingOptions.isEmpty {
                    VStack(spacing: 0) {
                        Divider()
                        HStack(spacing: 12) {
                            Button(action: {
                                if SharedDefaults.shared.isTrialExpired && !SharedDefaults.shared.isPremium {
                                    showPaywall = true
                                } else if !SharedDefaults.shared.canUploadPhoto {
                                    // Trial user hit 3 photo limit
                                    showPaywall = true
                                } else {
                                    showImagePicker = true
                                }
                            }) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor((isTrialExpired || !SharedDefaults.shared.canUploadPhoto) ? .gray.opacity(0.5) : .gray)
                            }

                            HStack {
                                TextField("iMessage", text: $inputText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(20)

                            Button(action: sendMessage) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(inputText.isEmpty ? Color.gray.opacity(0.5) : Color.blue)
                            }
                            .disabled(inputText.isEmpty || isLoading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(UIColor.systemBackground))
                    }
                }
            }
            .navigationTitle("Disguise.AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // Only show conversation history for premium users
                    if SharedDefaults.shared.isPremium {
                        Button(action: { showHistory = true }) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    } else {
                        // Trial users see locked icon that prompts upgrade
                        Button(action: { showPaywall = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 12))
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundColor(.gray.opacity(0.5))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                ConversationHistoryView(
                    messages: messages,
                    onNewChat: {
                        // Save current conversation to history first
                        if !messages.isEmpty {
                            SharedDefaults.shared.saveCurrentConversation()
                        }
                        // Clear current conversation and start fresh
                        messages.removeAll()
                        SharedDefaults.shared.clearChatHistory()
                        conversationStep = 3  // Skip onboarding for existing users
                        showHistory = false
                        // Start new conversation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showWelcomeBackMessage()
                        }
                    },
                    onLoadConversation: { savedMessages in
                        // Save current conversation first if it has messages
                        if !messages.isEmpty {
                            SharedDefaults.shared.saveCurrentConversation()
                        }
                        // Load the selected conversation
                        messages.removeAll()
                        SharedDefaults.shared.clearChatHistory()
                        for item in savedMessages {
                            if let text = item["text"] as? String,
                               let isUser = item["isUser"] as? Bool {
                                messages.append(ChatMessage(text: text, isUser: isUser))
                                SharedDefaults.shared.appendChatMessage(text: text, isUser: isUser)
                            }
                        }
                        conversationStep = 3
                        showHistory = false
                    },
                    onDismiss: {
                        showHistory = false
                    }
                )
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(onReset: onReset)
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $selectedImage)
            }
            .onChange(of: selectedImage) { image in
                if let image = image {
                    // Start the context flow instead of sending immediately
                    startImageContextFlow(image)
                }
            }
            .onAppear {
                if !hasLoadedHistory {
                    hasLoadedHistory = true
                    loadChatHistory()
                    checkTrialStatus()
                }
                // Restore last active time
                lastActiveTime = Date()
            }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .active:
                    // App came back to foreground
                    let timeSinceLastActive = Date().timeIntervalSince(lastActiveTime)
                    let fiveMinutes: TimeInterval = 5 * 60

                    if timeSinceLastActive < fiveMinutes {
                        // Within 5 minutes - keep current state, user picks up where they left off
                        print("Resuming session - \(Int(timeSinceLastActive))s since last active")
                        // Restore any pending input text
                        if inputText.isEmpty, let pendingText = UserDefaults.standard.string(forKey: "pendingInputText"), !pendingText.isEmpty {
                            inputText = pendingText
                            UserDefaults.standard.removeObject(forKey: "pendingInputText")
                        }
                    } else {
                        // More than 5 minutes - could refresh or show welcome back
                        print("Session expired - \(Int(timeSinceLastActive))s since last active")
                        // Clear any stale pending input
                        UserDefaults.standard.removeObject(forKey: "pendingInputText")
                        // Reload chat history from storage if needed
                        if messages.isEmpty {
                            loadChatHistory()
                        }
                    }
                    lastActiveTime = Date()

                case .inactive, .background:
                    // App going to background - save state
                    lastActiveTime = Date()
                    // Save current input text if any
                    if !inputText.isEmpty {
                        UserDefaults.standard.set(inputText, forKey: "pendingInputText")
                    }

                @unknown default:
                    break
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(onUpgrade: {
                    SharedDefaults.shared.isPremium = true
                    isTrialExpired = false
                    showPaywall = false
                }, onDismiss: {
                    showPaywall = false
                })
            }
        }
    }

    private func checkTrialStatus() {
        // Start trial if not started yet
        if SharedDefaults.shared.trialStartDate == nil {
            SharedDefaults.shared.trialStartDate = Date()
        }

        // Check if trial expired
        isTrialExpired = SharedDefaults.shared.isTrialExpired

        // Show paywall if trial just expired
        if isTrialExpired && !SharedDefaults.shared.isPremium {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showPaywall = true
            }
        }
    }

    private func loadChatHistory() {
        // First, load local history instantly (no network delay)
        let localHistory = SharedDefaults.shared.localChatHistory
        if !localHistory.isEmpty {
            for item in localHistory {
                if let text = item["text"] as? String,
                   let isUser = item["isUser"] as? Bool {
                    messages.append(ChatMessage(text: text, isUser: isUser))
                }
            }
            // User has history, skip onboarding questions
            conversationStep = 3

            // Sync with server in background (don't block UI)
            syncWithServerInBackground()
            return
        }

        // No local history - check if this is a verified returning user
        if SharedDefaults.shared.isVerifiedUser {
            // They've used the app before, try to get their history from server
            fetchServerHistory { success in
                if !success {
                    // No server history, show welcome back message
                    showWelcomeBackMessage()
                }
            }
        } else {
            // New user, show onboarding
            loadInitialMessage()
        }
    }

    private func syncWithServerInBackground() {
        guard let userId = SharedDefaults.shared.userId ?? SharedDefaults.shared.supabaseUserId,
              let url = URL(string: "\(ConfigManager.shared.serverBaseURL)/api/chat/\(userId)") else { return }

        // Sync silently in background - don't update UI since we already have local data
        URLSession.shared.dataTask(with: url).resume()
    }

    private func fetchServerHistory(completion: @escaping (Bool) -> Void) {
        guard let userId = SharedDefaults.shared.userId ?? SharedDefaults.shared.supabaseUserId,
              let url = URL(string: "\(ConfigManager.shared.serverBaseURL)/api/chat/\(userId)") else {
            completion(false)
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let history = json["chatHistory"] as? [[String: Any]], !history.isEmpty {
                    // Load messages from server
                    for item in history {
                        if let text = item["text"] as? String,
                           let isUser = item["isUser"] as? Bool {
                            messages.append(ChatMessage(text: text, isUser: isUser))
                            // Also save to local storage
                            SharedDefaults.shared.appendChatMessage(text: text, isUser: isUser)
                        }
                    }
                    conversationStep = 3
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }

    private func showWelcomeBackMessage() {
        let name = SharedDefaults.shared.userName ?? "there"
        let welcomeBack = "welcome back \(name)! send me a screenshot or tell me what's going on"
        messages.append(ChatMessage(text: welcomeBack, isUser: false))
        SharedDefaults.shared.appendChatMessage(text: welcomeBack, isUser: false)
        saveChatMessage(welcomeBack, isUser: false)
        conversationStep = 3
    }

    private func loadInitialMessage() {
        let name = SharedDefaults.shared.userName ?? "there"
        let vibes = SharedDefaults.shared.selectedVibes.joined(separator: ", ").lowercased()

        let greeting = "yo \(name)! \(vibes.isEmpty ? "" : "\(vibes) energy, i fw it. ")real quick before we get into it"

        messages.append(ChatMessage(text: greeting, isUser: false))
        saveChatMessage(greeting, isUser: false)

        // Show typing indicator briefly then ask first question
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isLoading = true
        }

        // Ask first question after 1.5 seconds (faster, less laggy feel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isLoading = false
            let question1 = "who you tryna text rn? like is it someone from an app, a crush, someone you just started talking to?"
            messages.append(ChatMessage(text: question1, isUser: false))
            saveChatMessage(question1, isUser: false)
            conversationStep = 1
        }
    }

    private func saveChatMessage(_ text: String, isUser: Bool) {
        // Save locally first (instant)
        SharedDefaults.shared.appendChatMessage(text: text, isUser: isUser)

        // Then sync to server in background
        guard let userId = SharedDefaults.shared.userId ?? SharedDefaults.shared.supabaseUserId,
              let url = URL(string: "\(ConfigManager.shared.serverBaseURL)/api/chat") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "userId": userId,
            "message": text,
            "isUser": isUser
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request).resume()
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }

        let userText = inputText
        inputText = ""

        messages.append(ChatMessage(text: userText, isUser: true))
        saveChatMessage(userText, isUser: true)

        // Show typing indicator
        isLoading = true

        // Random delay to feel human (1-2.5 seconds)
        let typingDelay = Double.random(in: 1.0...2.5)

        // Handle initial onboarding flow
        if conversationStep == 1 {
            // They answered Q1, now ask Q2
            DispatchQueue.main.asyncAfter(deadline: .now() + typingDelay) {
                isLoading = false
                let question2 = "bet. so what usually messes you up? like do you not know how to start, do convos die out, or you just don't know how to flirt without being weird lol"
                messages.append(ChatMessage(text: question2, isUser: false))
                saveChatMessage(question2, isUser: false)
                conversationStep = 2
            }
        } else if conversationStep == 2 {
            // They answered Q2, now ready to help
            DispatchQueue.main.asyncAfter(deadline: .now() + typingDelay) {
                isLoading = false
                let ready = "say less. send me a screenshot of the convo or just tell me what's going on and i'll help you out"
                messages.append(ChatMessage(text: ready, isUser: false))
                saveChatMessage(ready, isUser: false)
                conversationStep = 3

                // Show typing indicator then tip about settings
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    isLoading = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    isLoading = false
                    let tip = "oh and btw - the more you fill out in settings, the better i get at sounding like you. just tap the gear icon whenever"
                    messages.append(ChatMessage(text: tip, isUser: false))
                    saveChatMessage(tip, isUser: false)
                }
            }
        } else {
            // Normal conversation - use API
            APIService.shared.sendMessage(userText) { result in
                // Add extra delay after API returns to feel natural
                let responseDelay = Double.random(in: 0.5...1.5)
                DispatchQueue.main.asyncAfter(deadline: .now() + responseDelay) {
                    isLoading = false
                    switch result {
                    case .success(let response):
                        messages.append(ChatMessage(text: response, isUser: false))
                        saveChatMessage(response, isUser: false)
                    case .failure:
                        let errorMsg = "my bad, couldn't connect rn. try again?"
                        messages.append(ChatMessage(text: errorMsg, isUser: false))
                        saveChatMessage(errorMsg, isUser: false)
                    }
                }
            }
        }
    }

    private func startImageContextFlow(_ image: UIImage) {
        // Track photo upload for trial users
        if !SharedDefaults.shared.isPremium {
            SharedDefaults.shared.trialPhotoUploads += 1
        }

        // Store the image and show it instantly
        pendingImage = image
        messages.append(ChatMessage(text: "", isUser: true, image: image))
        saveChatMessage("[sent an image]", isUser: true)
        selectedImage = nil

        // Show options immediately - no delay
        let question = "who is this?"
        messages.append(ChatMessage(text: question, isUser: false))
        saveChatMessage(question, isUser: false)
        showingOptions = whoOptions
        imageContextStep = 1
    }

    private func optionTapped(_ option: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Add user's selection as a message
        messages.append(ChatMessage(text: option, isUser: true))
        saveChatMessage(option, isUser: true)
        showingOptions = []

        if imageContextStep == 1 {
            // They answered who, instantly show next question
            imageContextWho = option
            let question = "what do you need?"
            messages.append(ChatMessage(text: question, isUser: false))
            saveChatMessage(question, isUser: false)
            showingOptions = helpOptions
            imageContextStep = 2
        } else if imageContextStep == 2 {
            // They answered what help, send immediately - no "reading" message
            imageContextHelp = option

            // Send the image with context right away
            if let image = pendingImage {
                sendImageWithContext(image, who: imageContextWho, help: imageContextHelp)
            }

            // Reset
            imageContextStep = 0
            imageContextWho = ""
            imageContextHelp = ""
            pendingImage = nil
        }
    }

    private func sendImageWithContext(_ image: UIImage, who: String, help: String) {
        isLoading = true

        APIService.shared.sendImageWithContext(image, who: who, help: help) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let response):
                    messages.append(ChatMessage(text: response, isUser: false))
                    saveChatMessage(response, isUser: false)
                case .failure:
                    let errorMsg = "couldn't connect. try again?"
                    messages.append(ChatMessage(text: errorMsg, isUser: false))
                    saveChatMessage(errorMsg, isUser: false)
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

// MARK: - Chat Message Model
struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    var image: UIImage?
    var options: [String]?  // Quick tap options
}

// MARK: - Chat Bubble
struct ChatBubble: View {
    let message: ChatMessage

    // iMessage blue color
    private let iMessageBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    // iMessage gray color
    private let iMessageGray = Color(UIColor.systemGray5)

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser { Spacer(minLength: 60) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // Show image if present
                if let image = message.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240, maxHeight: 320)
                        .cornerRadius(18)
                }

                // Only show text bubble if there's text
                if !message.text.isEmpty {
                    Text(message.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(message.isUser ? iMessageBlue : iMessageGray)
                        .foregroundColor(message.isUser ? .white : .primary)
                        .cornerRadius(18)
                }
            }

            if !message.isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

// MARK: - Typing Indicator (iMessage style)
struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(i) * 0.2),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(UIColor.systemGray5))
        .cornerRadius(18)
        .onAppear { animating = true }
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    let onReset: () -> Void
    @Environment(\.dismiss) var dismiss

    @State private var userName = SharedDefaults.shared.userName ?? ""
    @State private var textSamples = SharedDefaults.shared.textSamples
    @State private var responseStyle = SharedDefaults.shared.responseStyle
    @State private var messageLength = Double(Int(SharedDefaults.shared.messageLength) ?? 2)
    @State private var emojiUsage = Double(Int(SharedDefaults.shared.emojiUsage) ?? 2)
    @State private var flirtiness = Double(Int(SharedDefaults.shared.flirtiness) ?? 1)

    // Deep personality questions
    @State private var noReplyThought: String = UserDefaults.standard.string(forKey: "noReplyThought") ?? ""
    @State private var whenYouLikeSomeone: String = UserDefaults.standard.string(forKey: "whenYouLikeSomeone") ?? ""
    @State private var whatKillsConvos: String = UserDefaults.standard.string(forKey: "whatKillsConvos") ?? ""
    @State private var quietConvoResponse: String = UserDefaults.standard.string(forKey: "quietConvoResponse") ?? ""
    @State private var biggestFear: String = UserDefaults.standard.string(forKey: "biggestFear") ?? ""
    @State private var howThingsEnd: String = UserDefaults.standard.string(forKey: "howThingsEnd") ?? ""
    @State private var confidenceLevel: String = UserDefaults.standard.string(forKey: "confidenceLevel") ?? ""
    @State private var whatYouWant: String = UserDefaults.standard.string(forKey: "whatYouWant") ?? ""

    // Subscription
    @State private var showSubscription = false

    var body: some View {
        NavigationView {
            Form {
                // MARK: - Profile
                Section {
                    TextField("Your Name", text: $userName)
                } header: {
                    Text("Profile")
                }

                // MARK: - Response Style
                Section {
                    Picker("Vibe", selection: $responseStyle) {
                        Text("Chill").tag("normal")
                        Text("Bold").tag("bold")
                        Text("Confident").tag("super-bold")
                        Text("Flirty").tag("spicy")
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Message Length: \(lengthLabel)")
                            .font(.subheadline)
                        Slider(value: $messageLength, in: 1...3, step: 1)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Emojis: \(emojiLabel)")
                            .font(.subheadline)
                        Slider(value: $emojiUsage, in: 1...3, step: 1)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Flirtiness: \(flirtLabel)")
                            .font(.subheadline)
                        Slider(value: $flirtiness, in: 1...3, step: 1)
                    }
                } header: {
                    Text("Response Style")
                }

                // MARK: - How You Think
                Section {
                    SettingsPicker(
                        title: "When they don't text back, your first thought is...",
                        options: [
                            "they're just busy",
                            "they're losing interest",
                            "i probably said something wrong",
                            "doesn't really bother me"
                        ],
                        selected: $noReplyThought
                    )

                    SettingsPicker(
                        title: "When you actually like someone, you...",
                        options: [
                            "play it cool, hide it",
                            "pull back to protect yourself",
                            "go all in, can't help it",
                            "test them to see if they're worth it"
                        ],
                        selected: $whenYouLikeSomeone
                    )

                    SettingsPicker(
                        title: "What usually kills your conversations?",
                        options: [
                            "i get too available",
                            "i don't show enough interest",
                            "convos just get boring",
                            "i overthink and mess it up"
                        ],
                        selected: $whatKillsConvos
                    )
                } header: {
                    Text("How You Think")
                } footer: {
                    Text("be honest - this helps me help you")
                }

                // MARK: - Your Patterns
                Section {
                    SettingsPicker(
                        title: "When a convo goes quiet, you...",
                        options: [
                            "double text, can't help it",
                            "wait it out, ball's in their court",
                            "assume it's over and move on",
                            "send something casual like a meme"
                        ],
                        selected: $quietConvoResponse
                    )

                    SettingsPicker(
                        title: "What scares you most about texting someone you like?",
                        options: [
                            "being left on read",
                            "coming on too strong",
                            "being boring or dry",
                            "showing how i actually feel"
                        ],
                        selected: $biggestFear
                    )

                    SettingsPicker(
                        title: "How do most of your talking stages end?",
                        options: [
                            "i ghost when it gets real",
                            "they lose interest first",
                            "it just fizzles out",
                            "i push them away somehow"
                        ],
                        selected: $howThingsEnd
                    )
                } header: {
                    Text("Your Patterns")
                }

                // MARK: - Real Talk
                Section {
                    SettingsPicker(
                        title: "How confident do you feel when texting?",
                        options: [
                            "pretty confident actually",
                            "depends who i'm talking to",
                            "usually a little anxious",
                            "always second-guessing myself"
                        ],
                        selected: $confidenceLevel
                    )

                    SettingsPicker(
                        title: "What are you really looking for?",
                        options: [
                            "something real",
                            "keeping it casual for now",
                            "validation, being honest",
                            "not really sure yet"
                        ],
                        selected: $whatYouWant
                    )
                } header: {
                    Text("Real Talk")
                } footer: {
                    Text("no judgment - knowing this helps me give better responses")
                }

                // MARK: - Your Texting Style
                Section {
                    TextEditor(text: $textSamples)
                        .frame(minHeight: 80)
                } header: {
                    Text("Example Texts You've Sent")
                } footer: {
                    Text("paste real messages so i can match your style")
                }

                // MARK: - Keyboard
                Section {
                    Button(action: openKeyboardSettings) {
                        HStack {
                            Text("Keyboard Settings")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Keyboard")
                }

                // MARK: - Subscription
                Section {
                    Button(action: { showSubscription = true }) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.yellow)
                            Text(SharedDefaults.shared.isPremium ? "Premium Active" : "Upgrade to Premium")
                                .foregroundColor(.primary)
                            Spacer()
                            if SharedDefaults.shared.isPremium {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Text("$9.99/mo")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                    }

                    // Trial countdown - show prominently for non-premium users
                    if !SharedDefaults.shared.isPremium {
                        TrialCountdownView()
                    }
                } header: {
                    Text("Subscription")
                }

                // MARK: - Data
                Section {
                    Button("Reset All Data", role: .destructive) {
                        SharedDefaults.shared.clearAll()
                        clearLocalSettings()
                        dismiss()
                        onReset()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveSettings() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showSubscription) {
                PaywallView(
                    onUpgrade: {
                        SharedDefaults.shared.isPremium = true
                        showSubscription = false
                    },
                    onDismiss: {
                        showSubscription = false
                    }
                )
            }
        }
    }

    private var lengthLabel: String {
        ["Short", "Medium", "Long"][Int(messageLength) - 1]
    }

    private var emojiLabel: String {
        ["None", "Some", "Lots"][Int(emojiUsage) - 1]
    }

    private var flirtLabel: String {
        ["Friendly", "Subtle", "Flirty"][Int(flirtiness) - 1]
    }

    private func saveSettings() {
        // Save locally
        SharedDefaults.shared.userName = userName
        SharedDefaults.shared.textSamples = textSamples
        SharedDefaults.shared.responseStyle = responseStyle
        SharedDefaults.shared.messageLength = String(Int(messageLength))
        SharedDefaults.shared.emojiUsage = String(Int(emojiUsage))
        SharedDefaults.shared.flirtiness = String(Int(flirtiness))

        UserDefaults.standard.set(noReplyThought, forKey: "noReplyThought")
        UserDefaults.standard.set(whenYouLikeSomeone, forKey: "whenYouLikeSomeone")
        UserDefaults.standard.set(whatKillsConvos, forKey: "whatKillsConvos")
        UserDefaults.standard.set(quietConvoResponse, forKey: "quietConvoResponse")
        UserDefaults.standard.set(biggestFear, forKey: "biggestFear")
        UserDefaults.standard.set(howThingsEnd, forKey: "howThingsEnd")
        UserDefaults.standard.set(confidenceLevel, forKey: "confidenceLevel")
        UserDefaults.standard.set(whatYouWant, forKey: "whatYouWant")

        // Sync to server so AI learns their style
        if let userId = SharedDefaults.shared.supabaseUserId ?? SharedDefaults.shared.userId {
            let settings: [String: Any] = [
                "name": userName,
                "textSamples": textSamples,
                "responseStyle": responseStyle,
                "messageLength": Int(messageLength),
                "emojiUsage": Int(emojiUsage),
                "flirtiness": Int(flirtiness),
                "personality": SharedDefaults.shared.selectedVibes,
                // Deep personality insights
                "noReplyThought": noReplyThought,
                "whenYouLikeSomeone": whenYouLikeSomeone,
                "whatKillsConvos": whatKillsConvos,
                "quietConvoResponse": quietConvoResponse,
                "biggestFear": biggestFear,
                "howThingsEnd": howThingsEnd,
                "confidenceLevel": confidenceLevel,
                "whatYouWant": whatYouWant
            ]

            SupabaseManager.shared.updateUserSettings(userId: userId, settings: settings) { _ in
                // Silent sync - don't block UI
            }
        }

        dismiss()
    }

    private func clearLocalSettings() {
        UserDefaults.standard.removeObject(forKey: "noReplyThought")
        UserDefaults.standard.removeObject(forKey: "whenYouLikeSomeone")
        UserDefaults.standard.removeObject(forKey: "whatKillsConvos")
        UserDefaults.standard.removeObject(forKey: "quietConvoResponse")
        UserDefaults.standard.removeObject(forKey: "biggestFear")
        UserDefaults.standard.removeObject(forKey: "howThingsEnd")
        UserDefaults.standard.removeObject(forKey: "confidenceLevel")
        UserDefaults.standard.removeObject(forKey: "whatYouWant")
    }

    private func openKeyboardSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Settings Picker Component
struct SettingsPicker: View {
    let title: String
    let options: [String]
    @Binding var selected: String

    var body: some View {
        Picker(title, selection: $selected) {
            Text("Select...").tag("")
            ForEach(options, id: \.self) { option in
                Text(option).tag(option)
            }
        }
    }
}

// MARK: - Helper Views
struct VibeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? Color(red: 0.13, green: 0.77, blue: 0.37) : Color(.secondarySystemBackground))
                .cornerRadius(20)
        }
    }
}

struct InstructionCard: View {
    let icon: String
    let title: String
    let description: String
    var isComplete: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isComplete ? .green : Color(red: 0.13, green: 0.77, blue: 0.37))
                    .frame(width: 40)

                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .offset(x: 12, y: -12)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(isComplete ? .green : .primary)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isComplete ? Color.green.opacity(0.1) : Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Scale Button Style (clean press effect)
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
    }
}

// MARK: - Paywall View
struct PaywallView: View {
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    @StateObject private var storeManager = StoreManager.shared
    @State private var showError = false

    private var paywallTitle: String {
        if !SharedDefaults.shared.canUploadPhoto {
            return "You've used all 3 screenshots"
        } else if SharedDefaults.shared.isTrialExpired {
            return "Your free trial ended"
        } else {
            return "Unlock Premium"
        }
    }

    private var paywallSubtitle: String {
        if !SharedDefaults.shared.canUploadPhoto {
            return "Upgrade for unlimited screenshot analysis and personalized responses"
        } else if SharedDefaults.shared.isTrialExpired {
            return "Upgrade to keep the convo going"
        } else {
            let photosLeft = SharedDefaults.shared.trialPhotosRemaining
            return "Trial: \(photosLeft) screenshot\(photosLeft == 1 ? "" : "s") left, basic responses only"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Close button
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.gray.opacity(0.6))
                }
                .padding()
            }

            Spacer()

            // Icon
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(.yellow)
                .padding(.bottom, 20)

            // Title - dynamic based on what limit they hit
            Text(paywallTitle)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)

            Text(paywallSubtitle)
                .font(.system(size: 17))
                .foregroundColor(.secondary)
                .padding(.top, 4)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            // Features - show what they're missing
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "camera.fill", text: "Unlimited screenshots", isLocked: !SharedDefaults.shared.canUploadPhoto)
                FeatureRow(icon: "person.fill", text: "Personalized responses", isLocked: true)
                FeatureRow(icon: "clock.arrow.circlepath", text: "Conversation history", isLocked: true)
                FeatureRow(icon: "sparkles", text: "AI that sounds like you", isLocked: true)
            }
            .padding(.top, 40)
            .padding(.horizontal, 40)

            Spacer()

            // Pricing
            VStack(spacing: 8) {
                Text(storeManager.priceString)
                    .font(.system(size: 32, weight: .bold))
                Text("Cancel anytime")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)

            // Error message
            if let error = storeManager.errorMessage {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }

            // Upgrade button
            Button(action: handleUpgrade) {
                if storeManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                } else {
                    Text("Upgrade Now")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
            }
            .background(Color(red: 0.0, green: 0.48, blue: 1.0))
            .cornerRadius(14)
            .padding(.horizontal, 24)
            .disabled(storeManager.isLoading)

            // Restore purchases
            Button(action: handleRestore) {
                Text("Restore Purchases")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
            }
            .padding(.top, 12)

            // Continue with limited
            Button(action: onDismiss) {
                Text("Continue with limited features")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .onAppear {
            Task {
                await storeManager.loadProducts()
            }
        }
    }

    private func handleUpgrade() {
        Task {
            let success = await storeManager.purchase()
            if success {
                onUpgrade()
            }
        }
    }

    private func handleRestore() {
        Task {
            await storeManager.restorePurchases()
            if SharedDefaults.shared.isPremium {
                onUpgrade()
            }
        }
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
    let icon: String
    let text: String
    var isLocked: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isLocked ? .orange : Color(red: 0.0, green: 0.48, blue: 1.0))
                    .frame(width: 24)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                        .offset(x: 10, y: -8)
                }
            }
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(isLocked ? .secondary : .primary)
            Spacer()
            if isLocked {
                Text("Premium")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(6)
            }
        }
    }
}

// MARK: - Trial Countdown View
struct TrialCountdownView: View {
    private var daysRemaining: Int {
        SharedDefaults.shared.trialDaysRemaining
    }

    private var photosRemaining: Int {
        SharedDefaults.shared.trialPhotosRemaining
    }

    private var trialProgress: Double {
        // Progress from 0 to 1 (7 days to 0 days)
        Double(7 - daysRemaining) / 7.0
    }

    var body: some View {
        VStack(spacing: 12) {
            // Days remaining display
            HStack(spacing: 16) {
                // Countdown circle
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                        .frame(width: 60, height: 60)

                    // Progress circle (counts down)
                    Circle()
                        .trim(from: 0, to: 1 - trialProgress)
                        .stroke(
                            daysRemaining <= 2 ? Color.red : Color(red: 0.0, green: 0.48, blue: 1.0),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))

                    // Days number
                    VStack(spacing: 0) {
                        Text("\(daysRemaining)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(daysRemaining <= 2 ? .red : .primary)
                        Text("days")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    if daysRemaining > 0 {
                        Text("Free Trial")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") remaining")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Trial Ended")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.red)
                        Text("Upgrade to continue")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)

            // Trial limitations info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12))
                        .foregroundColor(photosRemaining == 0 ? .red : .orange)
                    Text("\(photosRemaining)/3 screenshots remaining")
                        .font(.system(size: 13))
                        .foregroundColor(photosRemaining == 0 ? .red : .secondary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("Basic responses only")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("No conversation history")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Conversation History View
struct ConversationHistoryView: View {
    let messages: [ChatMessage]
    let onNewChat: () -> Void
    let onLoadConversation: ([[String: Any]]) -> Void
    let onDismiss: () -> Void

    @State private var savedConversations: [[String: Any]] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                List {
                    // Current conversation
                    if !messages.isEmpty {
                        Section {
                            Button(action: onDismiss) {
                                ConversationRow(
                                    title: "Current Conversation",
                                    preview: messages.last?.text ?? "",
                                    messageCount: messages.count,
                                    isActive: true
                                )
                            }
                        } header: {
                            Text("Active")
                        }
                    }

                    // Previous conversations
                    if !savedConversations.isEmpty {
                        Section {
                            ForEach(Array(savedConversations.enumerated()), id: \.offset) { index, convo in
                                Button(action: {
                                    if let msgs = convo["messages"] as? [[String: Any]] {
                                        onLoadConversation(msgs)
                                    }
                                }) {
                                    ConversationRow(
                                        title: formatDate(convo["createdAt"] as? Double),
                                        preview: convo["preview"] as? String ?? "Conversation",
                                        messageCount: (convo["messages"] as? [[String: Any]])?.count ?? 0,
                                        isActive: false
                                    )
                                }
                            }
                            .onDelete(perform: deleteConversation)
                        } header: {
                            Text("Previous")
                        }
                    }
                }
                .listStyle(.insetGrouped)

                // Empty state
                if messages.isEmpty && savedConversations.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No conversations yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Start chatting to see your history here")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                }

                // New Chat Button
                Button(action: onNewChat) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                        Text("New Conversation")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(red: 0.0, green: 0.48, blue: 1.0))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                savedConversations = SharedDefaults.shared.savedConversations
            }
        }
    }

    private func formatDate(_ timestamp: Double?) -> String {
        guard let timestamp = timestamp else { return "Conversation" }
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func deleteConversation(at offsets: IndexSet) {
        for index in offsets {
            if let id = savedConversations[index]["id"] as? String {
                SharedDefaults.shared.deleteConversation(id: id)
            }
        }
        savedConversations = SharedDefaults.shared.savedConversations
    }
}

// MARK: - Conversation Row
struct ConversationRow: View {
    let title: String
    let preview: String
    let messageCount: Int
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isActive ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color.gray.opacity(0.3))
                    .frame(width: 44, height: 44)
                Image(systemName: "message.fill")
                    .font(.system(size: 18))
                    .foregroundColor(isActive ? .white : .gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Text(preview.prefix(40) + (preview.count > 40 ? "..." : ""))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(messageCount) msgs")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}
