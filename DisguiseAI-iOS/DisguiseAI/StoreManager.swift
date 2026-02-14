import Foundation
import StoreKit

class StoreManager: ObservableObject {
    static let shared = StoreManager()

    // Your product ID - set this up in App Store Connect
    static let premiumMonthlyID = "com.disguiseai.premium.monthly"

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var updateListenerTask: Task<Void, Error>?

    init() {
        updateListenerTask = listenForTransactions()

        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Load Products
    @MainActor
    func loadProducts() async {
        do {
            let productIDs = [StoreManager.premiumMonthlyID]
            products = try await Product.products(for: productIDs)
            print("Loaded \(products.count) products")
        } catch {
            print("Failed to load products: \(error)")
            errorMessage = "Failed to load subscription options"
        }
    }

    // MARK: - Purchase
    @MainActor
    func purchase() async -> Bool {
        guard let product = products.first else {
            errorMessage = "Product not available. Please try again later."
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)

                // Update purchased status
                purchasedProductIDs.insert(transaction.productID)
                updatePremiumStatus(true)

                // Finish the transaction
                await transaction.finish()

                isLoading = false
                return true

            case .userCancelled:
                isLoading = false
                return false

            case .pending:
                isLoading = false
                errorMessage = "Purchase is pending approval"
                return false

            @unknown default:
                isLoading = false
                return false
            }
        } catch {
            isLoading = false
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            print("Purchase error: \(error)")
            return false
        }
    }

    // MARK: - Restore Purchases
    @MainActor
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil

        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Failed to restore purchases"
            print("Restore error: \(error)")
        }
    }

    // MARK: - Check Current Entitlements
    @MainActor
    func updatePurchasedProducts() async {
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                if transaction.revocationDate == nil {
                    purchasedProductIDs.insert(transaction.productID)
                    updatePremiumStatus(true)
                } else {
                    purchasedProductIDs.remove(transaction.productID)
                }
            } catch {
                print("Transaction verification failed: \(error)")
            }
        }
    }

    // MARK: - Listen for Transactions
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)

                    await MainActor.run {
                        if transaction.revocationDate == nil {
                            self.purchasedProductIDs.insert(transaction.productID)
                            self.updatePremiumStatus(true)
                        } else {
                            self.purchasedProductIDs.remove(transaction.productID)
                        }
                    }

                    await transaction.finish()
                } catch {
                    print("Transaction listener error: \(error)")
                }
            }
        }
    }

    // MARK: - Verify Transaction
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Update Premium Status
    private func updatePremiumStatus(_ isPremium: Bool) {
        SharedDefaults.shared.isPremium = isPremium

        // Also sync to server
        if isPremium, let userId = SharedDefaults.shared.userId ?? SharedDefaults.shared.supabaseUserId {
            syncPremiumToServer(userId: userId)
        }
    }

    private func syncPremiumToServer(userId: String) {
        // Sync premium status to Supabase
        guard let url = URL(string: "\(ConfigManager.shared.supabaseURL)/rest/v1/profiles?id=eq.\(userId)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ConfigManager.shared.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(ConfigManager.shared.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["is_premium": true])

        URLSession.shared.dataTask(with: request).resume()
    }

    // MARK: - Get Price String
    var priceString: String {
        guard let product = products.first else {
            return "$9.99/month"
        }
        return product.displayPrice + "/month"
    }
}

enum StoreError: Error {
    case failedVerification
    case productNotFound
}
