import Foundation
import StoreKit
import UIKit

// MARK: - Product Identifiers

enum ProductID: String, CaseIterable {
    case monthly = "com.IDKN.TodayRSS.premium.monthly"
    case yearly = "com.IDKN.TodayRSS.premium.yearly"
    case lifetime = "com.IDKN.TodayRSS.premium.lifetime"

    static var subscriptionIDs: [String] {
        [ProductID.monthly.rawValue, ProductID.yearly.rawValue]
    }

    static var allIDs: [String] {
        allCases.map { $0.rawValue }
    }
}

// MARK: - Subscription Status

enum SubscriptionStatus: Equatable {
    case notSubscribed
    case subscribed(expiryDate: Date?, willRenew: Bool)
    case lifetime

    var isActive: Bool {
        switch self {
        case .notSubscribed: return false
        case .subscribed, .lifetime: return true
        }
    }
}

// MARK: - Purchase Error

enum PurchaseError: LocalizedError {
    case productNotFound
    case purchaseFailed
    case purchaseCancelled
    case purchasePending
    case verificationFailed
    case unknown

    var errorDescription: String? {
        switch self {
        case .productNotFound: return "Product not found"
        case .purchaseFailed: return "Purchase failed"
        case .purchaseCancelled: return "Purchase was cancelled"
        case .purchasePending: return "Purchase is pending approval"
        case .verificationFailed: return "Could not verify purchase"
        case .unknown: return "An unknown error occurred"
        }
    }
}

// MARK: - Subscription Manager

@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    // MARK: - Published State

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isPremium: Bool = false
    private(set) var subscriptionStatus: SubscriptionStatus = .notSubscribed
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    // MARK: - Sorted Products

    var monthlyProduct: Product? {
        products.first { $0.id == ProductID.monthly.rawValue }
    }

    var yearlyProduct: Product? {
        products.first { $0.id == ProductID.yearly.rawValue }
    }

    var lifetimeProduct: Product? {
        products.first { $0.id == ProductID.lifetime.rawValue }
    }

    // MARK: - Private

    private let isPremiumKey = "viberss.isPremium"
    private let purchasedIDsKey = "viberss.purchasedProductIDs"
    private let lastVerificationKey = "viberss.lastVerification"

    private var updateListenerTask: Task<Void, Never>?

    // MARK: - Init

    private init() {
        loadCachedEntitlements()
        startTransactionListener()

        Task {
            await loadProducts()
            await verifyEntitlements()
        }
    }

    // Note: updateListenerTask is cancelled automatically when the manager is deallocated
    // since it only holds a weak reference to self

    // MARK: - Product Loading

    func loadProducts() async {
        isLoading = true
        errorMessage = nil

        do {
            let storeProducts = try await Product.products(for: ProductID.allIDs)

            // Sort: monthly, yearly, lifetime
            products = storeProducts.sorted { p1, p2 in
                let order: [String: Int] = [
                    ProductID.monthly.rawValue: 0,
                    ProductID.yearly.rawValue: 1,
                    ProductID.lifetime.rawValue: 2
                ]
                return (order[p1.id] ?? 99) < (order[p2.id] ?? 99)
            }

            print("✓ SubscriptionManager: Loaded \(products.count) products")
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
            print("✗ SubscriptionManager: Failed to load products - \(error)")
        }

        isLoading = false
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Transaction? {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        let result: Product.PurchaseResult

        do {
            result = try await product.purchase()
        } catch {
            errorMessage = error.localizedDescription
            throw PurchaseError.purchaseFailed
        }

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await handleTransaction(transaction)
            await transaction.finish()
            print("✓ SubscriptionManager: Purchase successful - \(product.id)")
            return transaction

        case .userCancelled:
            throw PurchaseError.purchaseCancelled

        case .pending:
            throw PurchaseError.purchasePending

        @unknown default:
            throw PurchaseError.unknown
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        // Sync with App Store
        try await AppStore.sync()

        // Re-verify all entitlements
        await verifyEntitlements()

        print("✓ SubscriptionManager: Purchases restored")
    }

    // MARK: - Offer Code Redemption

    @MainActor
    func presentOfferCodeRedeemSheet() async {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            print("✗ SubscriptionManager: No window scene available")
            return
        }

        do {
            try await AppStore.presentOfferCodeRedeemSheet(in: windowScene)
            // After redemption, verify entitlements
            await verifyEntitlements()
            print("✓ SubscriptionManager: Offer code redeemed")
        } catch {
            print("✗ SubscriptionManager: Offer code redemption failed - \(error)")
        }
    }

    // MARK: - Transaction Listener

    private func startTransactionListener() {
        updateListenerTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }

                if case .verified(let transaction) = result {
                    await MainActor.run {
                        Task {
                            await self.handleTransaction(transaction)
                        }
                    }
                    await transaction.finish()
                }
            }
        }
    }

    private func handleTransaction(_ transaction: Transaction) async {
        // Check if transaction is still valid (not revoked/expired)
        if transaction.revocationDate == nil {
            purchasedProductIDs.insert(transaction.productID)
        } else {
            purchasedProductIDs.remove(transaction.productID)
        }

        await updatePremiumStatus()
        persistEntitlements()
    }

    // MARK: - Entitlement Verification

    func verifyEntitlements() async {
        var validProductIDs: Set<String> = []

        // Check current entitlements (auto-verified by StoreKit 2)
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                // Check if not revoked
                if transaction.revocationDate == nil {
                    validProductIDs.insert(transaction.productID)
                }
            }
        }

        purchasedProductIDs = validProductIDs
        await updatePremiumStatus()
        persistEntitlements()

        print("✓ SubscriptionManager: Verified entitlements - Premium: \(isPremium)")
    }

    private func updatePremiumStatus() async {
        // Check for lifetime purchase first
        if purchasedProductIDs.contains(ProductID.lifetime.rawValue) {
            isPremium = true
            subscriptionStatus = .lifetime
            return
        }

        // Check for active subscription
        for productID in ProductID.subscriptionIDs {
            if purchasedProductIDs.contains(productID) {
                // Get subscription details
                if let status = try? await getSubscriptionStatus(for: productID) {
                    isPremium = true
                    subscriptionStatus = status
                    return
                }
            }
        }

        // No active entitlements
        isPremium = false
        subscriptionStatus = .notSubscribed
    }

    private func getSubscriptionStatus(for productID: String) async throws -> SubscriptionStatus? {
        guard let product = products.first(where: { $0.id == productID }),
              let subscription = product.subscription else {
            return nil
        }

        // Get subscription status
        guard let statuses = try? await subscription.status,
              let status = statuses.first else {
            return nil
        }

        switch status.state {
        case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
            if case .verified(let renewalInfo) = status.renewalInfo {
                let willRenew = renewalInfo.willAutoRenew

                if case .verified(let transaction) = status.transaction {
                    return .subscribed(expiryDate: transaction.expirationDate, willRenew: willRenew)
                }
            }
            return .subscribed(expiryDate: nil, willRenew: true)

        case .expired, .revoked:
            return nil

        default:
            return nil
        }
    }

    // MARK: - Verification Helper

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PurchaseError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Persistence

    private func persistEntitlements() {
        UserDefaults.standard.set(isPremium, forKey: isPremiumKey)

        if let data = try? JSONEncoder().encode(Array(purchasedProductIDs)) {
            UserDefaults.standard.set(data, forKey: purchasedIDsKey)
        }

        UserDefaults.standard.set(Date(), forKey: lastVerificationKey)
    }

    private func loadCachedEntitlements() {
        isPremium = UserDefaults.standard.bool(forKey: isPremiumKey)

        if let data = UserDefaults.standard.data(forKey: purchasedIDsKey),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            purchasedProductIDs = Set(ids)
        }

        // Update status based on cached data
        if purchasedProductIDs.contains(ProductID.lifetime.rawValue) {
            subscriptionStatus = .lifetime
        } else if !purchasedProductIDs.isEmpty {
            subscriptionStatus = .subscribed(expiryDate: nil, willRenew: true)
        }
    }

    // MARK: - Debug

    #if DEBUG
    func simulatePremium(_ enabled: Bool) {
        isPremium = enabled
        subscriptionStatus = enabled ? .lifetime : .notSubscribed
        persistEntitlements()
        print("⚙️ SubscriptionManager: Simulated premium = \(enabled)")
    }
    #endif
}
