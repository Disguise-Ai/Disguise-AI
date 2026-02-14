import UIKit
import Photos

class KeyboardViewController: UIInputViewController {

    // UI Elements
    private var containerView: UIView!
    private var statusLabel: UILabel!
    private var questionLabel: UILabel!
    private var optionsStack: UIStackView!
    private var responseStack: UIStackView!
    private var globeButton: UIButton!

    // State
    private var responses: [String] = []
    private var isLoading = false
    private var lastScreenshotId: String?
    private var pollTimer: Timer?

    // Context flow
    private var pendingImageData: Data?
    private var contextStep = 0
    private var contextWho = ""
    private var contextHelp = ""

    // Use Supabase Edge Function instead of local server
    private var analyzeImageURL: String {
        return "\(ConfigManager.shared.supabaseURL)/functions/v1/analyze-image"
    }

    private var supabaseAnonKey: String {
        return ConfigManager.shared.supabaseAnonKey
    }

    private let whoOptions = ["crush", "dating app", "ex", "friend"]
    private let helpOptions = ["respond", "start convo", "what to say", "keep going"]

    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Set keyboard height constraint
        if heightConstraint == nil, let inputView = inputView {
            heightConstraint = inputView.heightAnchor.constraint(equalToConstant: 260)
            heightConstraint?.priority = .defaultHigh
            heightConstraint?.isActive = true
        }

        checkAndStart()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        globeButton = UIButton(type: .system)
        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.tintColor = .tertiaryLabel
        globeButton.translatesAutoresizingMaskIntoConstraints = false
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        view.addSubview(globeButton)

        statusLabel = UILabel()
        statusLabel.font = .systemFont(ofSize: 18, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(statusLabel)

        questionLabel = UILabel()
        questionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        questionLabel.textAlignment = .center
        questionLabel.textColor = .secondaryLabel
        questionLabel.translatesAutoresizingMaskIntoConstraints = false
        questionLabel.isHidden = true
        containerView.addSubview(questionLabel)

        optionsStack = UIStackView()
        optionsStack.axis = .vertical
        optionsStack.spacing = 10
        optionsStack.distribution = .fillEqually
        optionsStack.translatesAutoresizingMaskIntoConstraints = false
        optionsStack.isHidden = true
        containerView.addSubview(optionsStack)

        responseStack = UIStackView()
        responseStack.axis = .vertical
        responseStack.spacing = 8
        responseStack.translatesAutoresizingMaskIntoConstraints = false
        responseStack.isHidden = true
        containerView.addSubview(responseStack)

        for i in 0..<3 {
            let btn = createResponseButton(tag: i)
            responseStack.addArrangedSubview(btn)
        }

        NSLayoutConstraint.activate([
            globeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            globeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            globeButton.widthAnchor.constraint(equalToConstant: 28),
            globeButton.heightAnchor.constraint(equalToConstant: 28),

            containerView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            containerView.bottomAnchor.constraint(equalTo: globeButton.topAnchor, constant: -8),

            statusLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            questionLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            questionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            questionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            optionsStack.topAnchor.constraint(equalTo: questionLabel.bottomAnchor, constant: 12),
            optionsStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            optionsStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            optionsStack.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -4),

            responseStack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 4),
            responseStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            responseStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            responseStack.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -4)
        ])
    }

    private func createOptionButton(title: String, tag: Int) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        btn.setTitleColor(.label, for: .normal)
        btn.backgroundColor = UIColor.secondarySystemBackground
        btn.layer.cornerRadius = 10
        btn.tag = tag
        btn.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
        btn.addTarget(self, action: #selector(optionTouchDown(_:)), for: .touchDown)
        btn.addTarget(self, action: #selector(optionTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 46).isActive = true
        return btn
    }

    @objc private func optionTouchDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            sender.alpha = 0.85
        }
    }

    @objc private func optionTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = .identity
            sender.alpha = 1.0
        }
    }

    private func createResponseButton(tag: Int) -> UIButton {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        btn.titleLabel?.numberOfLines = 2
        btn.titleLabel?.lineBreakMode = .byTruncatingTail
        btn.contentHorizontalAlignment = .left
        btn.setTitleColor(.label, for: .normal)
        btn.backgroundColor = .secondarySystemBackground
        btn.layer.cornerRadius = 12
        btn.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        btn.tag = tag
        btn.addTarget(self, action: #selector(responseTapped(_:)), for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 52).isActive = true
        return btn
    }

    private func checkAndStart() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            startWatching()
        } else {
            statusLabel.text = "open disguise app\nto allow photos"
            statusLabel.textColor = .secondaryLabel
        }
    }

    private func startWatching() {
        lastScreenshotId = getLatestScreenshotId()
        showWaiting()

        // Fast polling - 0.4 seconds
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.checkForNew()
        }
    }

    private func showWaiting() {
        contextStep = 0
        pendingImageData = nil
        contextWho = ""
        contextHelp = ""

        statusLabel.text = "screenshot a convo\ni'll help you reply"
        statusLabel.textColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        statusLabel.isHidden = false
        questionLabel.isHidden = true
        optionsStack.isHidden = true
        responseStack.isHidden = true
    }

    private func getLatestScreenshotId() -> String? {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 1

        guard let collection = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil).firstObject else { return nil }
        return PHAsset.fetchAssets(in: collection, options: opts).firstObject?.localIdentifier
    }

    private func checkForNew() {
        guard !isLoading, contextStep == 0 else { return }

        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 1

        guard let collection = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil).firstObject,
              let asset = PHAsset.fetchAssets(in: collection, options: opts).firstObject else { return }

        if asset.localIdentifier != lastScreenshotId {
            lastScreenshotId = asset.localIdentifier
            pollTimer?.invalidate()
            captureImage(asset)
        }
    }

    private func captureImage(_ asset: PHAsset) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Check trial photo limit (5 photos for trial users)
        if !SharedDefaults.shared.isPremium && !SharedDefaults.shared.canUploadPhoto {
            showError(message: "photo limit reached\nupgrade in app")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.startWatching()
            }
            return
        }

        // Track photo upload for trial users
        if !SharedDefaults.shared.isPremium {
            SharedDefaults.shared.trialPhotoUploads += 1
        }

        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat  // High quality so AI can read text
        opts.isSynchronous = false
        opts.isNetworkAccessAllowed = false
        opts.resizeMode = .exact

        // Get larger image so AI can read the text clearly
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 1080, height: 1920), contentMode: .aspectFit, options: opts) { [weak self] image, _ in
            guard let self = self, let image = image else {
                DispatchQueue.main.async { self?.showError(message: "couldn't load image") }
                return
            }

            // Compress on background thread - higher quality for text readability
            DispatchQueue.global(qos: .userInitiated).async {
                let data = image.jpegData(compressionQuality: 0.7)  // Higher quality
                DispatchQueue.main.async {
                    self.pendingImageData = data
                    self.showQuestion1()
                }
            }
        }
    }

    private func showQuestion1() {
        contextStep = 1
        statusLabel.isHidden = true
        questionLabel.text = "who is this?"
        questionLabel.isHidden = false

        optionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let row1 = UIStackView()
        row1.axis = .horizontal
        row1.spacing = 10
        row1.distribution = .fillEqually

        let row2 = UIStackView()
        row2.axis = .horizontal
        row2.spacing = 10
        row2.distribution = .fillEqually

        for (i, option) in whoOptions.enumerated() {
            let btn = createOptionButton(title: option, tag: i)
            if i < 2 { row1.addArrangedSubview(btn) }
            else { row2.addArrangedSubview(btn) }
        }

        optionsStack.addArrangedSubview(row1)
        optionsStack.addArrangedSubview(row2)
        optionsStack.isHidden = false
    }

    private func showQuestion2() {
        contextStep = 2
        questionLabel.text = "what do you need?"

        optionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let row1 = UIStackView()
        row1.axis = .horizontal
        row1.spacing = 10
        row1.distribution = .fillEqually

        let row2 = UIStackView()
        row2.axis = .horizontal
        row2.spacing = 10
        row2.distribution = .fillEqually

        for (i, option) in helpOptions.enumerated() {
            let btn = createOptionButton(title: option, tag: i)
            if i < 2 { row1.addArrangedSubview(btn) }
            else { row2.addArrangedSubview(btn) }
        }

        optionsStack.addArrangedSubview(row1)
        optionsStack.addArrangedSubview(row2)
    }

    @objc private func optionTapped(_ sender: UIButton) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if contextStep == 1 {
            contextWho = whoOptions[sender.tag]
            showQuestion2()
        } else if contextStep == 2 {
            contextHelp = helpOptions[sender.tag]
            analyzeWithContext()
        }
    }

    private func analyzeWithContext() {
        guard let data = pendingImageData else {
            showError()
            return
        }

        isLoading = true
        questionLabel.isHidden = true
        optionsStack.isHidden = true

        // Show loading indicator instead of text
        statusLabel.text = "•••"
        statusLabel.textColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        statusLabel.isHidden = false

        sendToServer(data)
    }

    private func sendToServer(_ imageData: Data, retryCount: Int = 0) {
        guard let url = URL(string: analyzeImageURL) else {
            showError()
            return
        }

        // Convert image to base64
        let base64Image = imageData.base64EncodedString()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 45  // Allow time for AI processing

        let isTrialUser = !SharedDefaults.shared.isPremium

        let body: [String: Any] = [
            "imageBase64": base64Image,
            "contextWho": contextWho,
            "contextHelp": contextHelp,
            "isTrialUser": isTrialUser,
            "userName": SharedDefaults.shared.userName ?? "",
            "textSamples": SharedDefaults.shared.textSamples,
            "fromKeyboard": true  // Flag to get suggestions format
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            showError(message: "couldn't send\ntry again")
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                // Check for network error
                if let error = error {
                    let nsError = error as NSError
                    print("Keyboard network error: \(error.localizedDescription) (code: \(nsError.code))")

                    // Retry once if network error
                    if retryCount < 1 {
                        print("Retrying...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self?.sendToServer(imageData, retryCount: retryCount + 1)
                        }
                        return
                    }

                    // Show specific error message
                    if nsError.code == -1009 {
                        self?.showError(message: "no internet\ncheck connection")
                    } else if nsError.code == -1001 {
                        self?.showError(message: "taking too long\ntry again")
                    } else {
                        self?.showError(message: "connection failed\ntry again")
                    }
                    return
                }

                // Check HTTP status
                if let httpResponse = response as? HTTPURLResponse {
                    print("Keyboard response status: \(httpResponse.statusCode)")
                    if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                        self?.showError(message: "server error\ntry again")
                        return
                    }
                }

                self?.isLoading = false

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let reply = json["reply"] as? String else {
                    print("Keyboard: Invalid response data")
                    self?.showError(message: "bad response\ntry again")
                    return
                }

                // Parse suggestions from the reply text
                let suggestions = self?.parseSuggestions(from: reply) ?? []
                if suggestions.isEmpty {
                    self?.showError(message: "no suggestions\ntry again")
                    return
                }

                self?.showSuggestions(suggestions)
            }
        }.resume()
    }

    private func parseSuggestions(from text: String) -> [String] {
        // Try to extract quoted suggestions first
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

        // Fallback: look for numbered options like "1. text" or "1) text"
        let numberedPattern = "(?:^|\\n)\\s*[123][.)]\\s*[\"']?([^\"'\\n]{5,100})[\"']?"
        if let regex = try? NSRegularExpression(pattern: numberedPattern, options: [.anchorsMatchLines]) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)

            let suggestions = matches.compactMap { match -> String? in
                if let range = Range(match.range(at: 1), in: text) {
                    return String(text[range]).trimmingCharacters(in: .whitespaces)
                }
                return nil
            }

            if suggestions.count >= 2 {
                return Array(suggestions.prefix(3))
            }
        }

        // Final fallback
        return ["hey what's up", "that's cool", "tell me more"]
    }

    private func showSuggestions(_ suggestions: [String]) {
        contextStep = 3
        responses = suggestions
        statusLabel.isHidden = true
        questionLabel.isHidden = true
        optionsStack.isHidden = true
        responseStack.isHidden = false

        let buttons = responseStack.arrangedSubviews.compactMap { $0 as? UIButton }
        for (i, btn) in buttons.enumerated() {
            if i < suggestions.count {
                btn.setTitle(suggestions[i], for: .normal)
                btn.isHidden = false
            } else {
                btn.isHidden = true
            }
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @objc private func responseTapped(_ sender: UIButton) {
        guard sender.tag < responses.count else { return }
        textDocumentProxy.insertText(responses[sender.tag])
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Quick flash feedback
        sender.backgroundColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        sender.setTitleColor(.white, for: .normal)

        UIView.animate(withDuration: 0.2) {
            sender.backgroundColor = .secondarySystemBackground
            sender.setTitleColor(.label, for: .normal)
        }

        // Quick reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.startWatching()
        }
    }

    private func showError(message: String? = nil) {
        isLoading = false
        contextStep = 0
        pendingImageData = nil

        // Check if Full Access is enabled (required for network)
        if !isFullAccessEnabled {
            statusLabel.text = "enable full access\nin keyboard settings"
        } else {
            statusLabel.text = message ?? "couldn't connect\ntap to retry"
        }

        statusLabel.textColor = .systemOrange
        statusLabel.isHidden = false
        questionLabel.isHidden = true
        optionsStack.isHidden = true
        responseStack.isHidden = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.startWatching()
        }
    }

    private var isFullAccessEnabled: Bool {
        // Check if we can access pasteboard (requires Full Access)
        let pasteboard = UIPasteboard.general
        return pasteboard.hasStrings || pasteboard.hasImages || pasteboard.hasURLs
    }
}
