import Foundation
import RevenueCat

class StoreManager: ObservableObject {
    static let shared = StoreManager()

    // RevenueCat API Key - get this from RevenueCat dashboard
    static let revenueCatAPIKey = "YOUR_REVENUECAT_API_KEY"  // Replace with your key

    // Your entitlement ID from RevenueCat
    static let premiumEntitlementID = "premium"

    // Your product ID
    static let premiumMonthlyID = "com.disguiseai.premium.monthly"

    @Published var packages: [Package] = []
    @Published var isSubscribed = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private init() {
        // Configure RevenueCat
        Purchases.logLevel = .debug  // Set to .error for production
        Purchases.configure(withAPIKey: StoreManager.revenueCatAPIKey)

        // Set user ID if available
        if let userId = SharedDefaults.shared.userId ?? SharedDefaults.shared.supabaseUserId {
            Purchases.shared.logIn(userId) { _, _, _ in }
        }

        // Check subscription status
        Task {
            await checkSubscriptionStatus()
            await loadOfferings()
        }
    }

    // MARK: - Load Offerings
    @MainActor
    func loadOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            if let current = offerings.current {
                packages = current.availablePackages
                print("Loaded \(packages.count) packages")
            }
        } catch {
            print("Failed to load offerings: \(error)")
            errorMessage = "Failed to load subscription options"
        }
    }

    // MARK: - Check Subscription Status
    @MainActor
    func checkSubscriptionStatus() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let hasPremium = customerInfo.entitlements[StoreManager.premiumEntitlementID]?.isActive == true

            isSubscribed = hasPremium
            SharedDefaults.shared.isPremium = hasPremium

            // Sync to Supabase
            if hasPremium, let userId = SharedDefaults.shared.userId ?? SharedDefaults.shared.supabaseUserId {
                syncPremiumToSupabase(userId: userId, isPremium: true)
            }
        } catch {
            print("Failed to check subscription: \(error)")
        }
    }

    // MARK: - Purchase
    @MainActor
    func purchase() async -> Bool {
        guard let package = packages.first else {
            errorMessage = "Product not available. Please try again later."
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await Purchases.shared.purchase(package: package)

            let hasPremium = result.customerInfo.entitlements[StoreManager.premiumEntitlementID]?.isActive == true

            if hasPremium {
                isSubscribed = true
                SharedDefaults.shared.isPremium = true

                // Sync to Supabase
                if let userId = SharedDefaults.shared.userId ?? SharedDefaults.shared.supabaseUserId {
                    syncPremiumToSupabase(userId: userId, isPremium: true)
                }

                isLoading = false
                return true
            }

            isLoading = false
            return false

        } catch let error as ErrorCode {
            isLoading = false

            switch error {
            case .purchaseCancelledError:
                // User cancelled, not an error
                return false
            default:
                errorMessage = "Purchase failed. Please try again."
                print("Purchase error: \(error)")
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
            let customerInfo = try await Purchases.shared.restorePurchases()
            let hasPremium = customerInfo.entitlements[StoreManager.premiumEntitlementID]?.isActive == true

            isSubscribed = hasPremium
            SharedDefaults.shared.isPremium = hasPremium

            if hasPremium {
                if let userId = SharedDefaults.shared.userId ?? SharedDefaults.shared.supabaseUserId {
                    syncPremiumToSupabase(userId: userId, isPremium: true)
                }
            }

            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Failed to restore purchases"
            print("Restore error: \(error)")
        }
    }

    // MARK: - Sync Premium to Supabase
    private func syncPremiumToSupabase(userId: String, isPremium: Bool) {
        guard let url = URL(string: "\(ConfigManager.shared.supabaseURL)/rest/v1/profiles?id=eq.\(userId)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ConfigManager.shared.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(ConfigManager.shared.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["is_premium": isPremium])

        URLSession.shared.dataTask(with: request).resume()
    }

    // MARK: - Get Price String
    var priceString: String {
        guard let package = packages.first else {
            return "$9.99/month"
        }
        return package.localizedPriceString + "/month"
    }

    // MARK: - Login User (call when user signs in)
    func loginUser(userId: String) {
        Purchases.shared.logIn(userId) { customerInfo, _, error in
            if let error = error {
                print("RevenueCat login error: \(error)")
                return
            }

            Task { @MainActor in
                await self.checkSubscriptionStatus()
            }
        }
    }

    // MARK: - Logout User (call when user signs out)
    func logoutUser() {
        Purchases.shared.logOut { _, _ in }
        isSubscribed = false
    }
}
