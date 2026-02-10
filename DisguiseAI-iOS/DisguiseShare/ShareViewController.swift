import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    // MARK: - UI Elements
    private var containerView: UIView!
    private var imageView: UIImageView!
    private var suggestionsStackView: UIStackView!
    private var statusLabel: UILabel!
    private var closeButton: UIButton!
    private var doneButton: UIButton!
    private var loadingIndicator: UIActivityIndicatorView!

    // MARK: - State
    private var sharedImage: UIImage?
    private var suggestions: [String] = []

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        extractSharedContent()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        // Container
        containerView = UIView()
        containerView.backgroundColor = .systemBackground
        containerView.layer.cornerRadius = 16
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            containerView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.8)
        ])

        // Header
        let headerStack = UIStackView()
        headerStack.axis = .horizontal
        headerStack.distribution = .equalSpacing
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(headerStack)

        let titleLabel = UILabel()
        titleLabel.text = "Disguise.AI"
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)

        closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .systemGray
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(closeButton)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16)
        ])

        // Image preview
        imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        imageView.backgroundColor = .secondarySystemBackground
        imageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 16),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            imageView.heightAnchor.constraint(equalToConstant: 200)
        ])

        // Loading indicator
        loadingIndicator = UIActivityIndicatorView(style: .medium)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        containerView.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            loadingIndicator.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20)
        ])

        // Status label
        statusLabel = UILabel()
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16)
        ])

        // Suggestions stack
        suggestionsStackView = UIStackView()
        suggestionsStackView.axis = .vertical
        suggestionsStackView.spacing = 8
        suggestionsStackView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(suggestionsStackView)

        NSLayoutConstraint.activate([
            suggestionsStackView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            suggestionsStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            suggestionsStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16)
        ])

        // Done button
        doneButton = UIButton(type: .system)
        doneButton.setTitle("Done - Return to Keyboard", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.backgroundColor = UIColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1.0)
        doneButton.layer.cornerRadius = 12
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        doneButton.isHidden = true
        containerView.addSubview(doneButton)

        NSLayoutConstraint.activate([
            doneButton.topAnchor.constraint(equalTo: suggestionsStackView.bottomAnchor, constant: 16),
            doneButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            doneButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            doneButton.heightAnchor.constraint(equalToConstant: 50),
            doneButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - Share Extension Logic
    private func extractSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            showError("No content found")
            return
        }

        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] data, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self?.showError("Failed to load image: \(error.localizedDescription)")
                            return
                        }

                        var image: UIImage?
                        if let imageData = data as? Data {
                            image = UIImage(data: imageData)
                        } else if let url = data as? URL {
                            image = UIImage(contentsOfFile: url.path)
                        } else if let loadedImage = data as? UIImage {
                            image = loadedImage
                        }

                        if let image = image {
                            self?.sharedImage = image
                            self?.imageView.image = image
                            self?.analyzeImage(image)
                        } else {
                            self?.showError("Could not process image")
                        }
                    }
                }
                return
            }
        }

        showError("Please share an image/screenshot")
    }

    private func analyzeImage(_ image: UIImage) {
        statusLabel.text = "Analyzing conversation..."
        loadingIndicator.startAnimating()

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            showError("Failed to process image")
            return
        }

        let userId = SharedDefaults.shared.userId ?? "anonymous"

        APIService.shared.analyzeScreenshot(imageData: imageData, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                self?.loadingIndicator.stopAnimating()

                switch result {
                case .success(let suggestions):
                    self?.displaySuggestions(suggestions)
                case .failure(let error):
                    self?.showError("Couldn't analyze. Try again later.")
                    print("Error: \(error)")
                }
            }
        }
    }

    private func displaySuggestions(_ suggestions: [String]) {
        self.suggestions = suggestions

        suggestionsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Auto-copy the first (best) suggestion
        if let bestSuggestion = suggestions.first {
            UIPasteboard.general.string = bestSuggestion
            SharedDefaults.shared.pendingSuggestion = bestSuggestion
            statusLabel.text = "Best response copied! Tap another to switch:"
            statusLabel.textColor = UIColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1.0)

            // Haptic for auto-copy
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } else {
            statusLabel.text = "Tap to copy a response:"
        }

        for (index, suggestion) in suggestions.prefix(3).enumerated() {
            let button = createSuggestionButton(text: suggestion, index: index)
            // Mark first one as selected
            if index == 0 {
                button.configuration?.baseBackgroundColor = UIColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 0.2)
                button.layer.borderWidth = 2
                button.layer.borderColor = UIColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1.0).cgColor
                button.layer.cornerRadius = 10
            }
            suggestionsStackView.addArrangedSubview(button)
        }

        // Show done button
        doneButton.isHidden = false
    }

    private func createSuggestionButton(text: String, index: Int) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = text
        config.titleLineBreakMode = .byWordWrapping
        config.cornerStyle = .medium
        config.baseBackgroundColor = .secondarySystemBackground
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)

        let button = UIButton(configuration: config)
        button.titleLabel?.numberOfLines = 0
        button.contentHorizontalAlignment = .left
        button.tag = index
        button.addTarget(self, action: #selector(suggestionTapped(_:)), for: .touchUpInside)

        return button
    }

    @objc private func suggestionTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index < suggestions.count else { return }

        let text = suggestions[index]

        // Copy to clipboard
        UIPasteboard.general.string = text

        // Save to shared defaults so keyboard can access it
        SharedDefaults.shared.pendingContext = nil // Clear context
        SharedDefaults.shared.pendingSuggestion = text // Save for keyboard quick-insert
        var recent = SharedDefaults.shared.recentSuggestions
        recent.insert(text, at: 0)
        SharedDefaults.shared.recentSuggestions = recent

        // Reset all buttons appearance
        for case let button as UIButton in suggestionsStackView.arrangedSubviews {
            button.configuration?.baseBackgroundColor = .secondarySystemBackground
            button.configuration?.baseForegroundColor = .label
            button.layer.borderWidth = 0
        }

        // Show confirmation on tapped button
        sender.configuration?.baseBackgroundColor = UIColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1.0)
        sender.configuration?.baseForegroundColor = .white
        sender.configuration?.title = "Copied!"

        statusLabel.text = "Switch to keyboard to insert, or tap another"
        statusLabel.textColor = .secondaryLabel

        // Haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func showError(_ message: String) {
        statusLabel.text = message
        statusLabel.textColor = .systemRed
        loadingIndicator.stopAnimating()
    }

    @objc private func close() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
