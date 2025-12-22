import SwiftUI
import StoreKit

// MARK: - Paywall Trigger

enum PaywallTrigger {
    case atAGlance
    case feeds
    case newsReel
    case savedArticles
    case settings

    var title: String {
        switch self {
        case .atAGlance: return "Unlock At-a-Glance"
        case .feeds: return "Add More Sources"
        case .newsReel: return "Keep Swiping"
        case .savedArticles: return "Save More Articles"
        case .settings: return "Upgrade to Premium"
        }
    }

    var subtitle: String {
        switch self {
        case .atAGlance:
            return "See up to 4 articles with AI summaries in your At-a-Glance view"
        case .feeds:
            return "You've reached the limit of 5 sources. Upgrade to add unlimited feeds."
        case .newsReel:
            return "You've used all 10 swipes today. Upgrade for unlimited browsing."
        case .savedArticles:
            return "You've saved 10 articles. Upgrade to save unlimited articles."
        case .settings:
            return "Unlock all features and remove all limits"
        }
    }

    var icon: String {
        switch self {
        case .atAGlance: return "sparkles"
        case .feeds: return "antenna.radiowaves.left.and.right"
        case .newsReel: return "rectangle.stack"
        case .savedArticles: return "heart.fill"
        case .settings: return "star.fill"
        }
    }
}

// MARK: - Paywall View

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    let trigger: PaywallTrigger

    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    featuresSection
                    productsSection
                    purchaseButton
                    legalSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Restore") {
                        Task { await restorePurchases() }
                    }
                    .disabled(isPurchasing)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .onAppear {
                // Pre-select yearly as best value
                if selectedProduct == nil {
                    selectedProduct = subscriptionManager.yearlyProduct
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: trigger.icon)
                .font(.system(size: 48))
                .foregroundStyle(.orange.gradient)

            Text(trigger.title)
                .font(.roundedTitle2.bold())

            Text(trigger.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    // MARK: - Features

    @ViewBuilder
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(EntitlementManager.premiumFeatures, id: \.title) { feature in
                HStack(spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.orange)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.subheadline.weight(.medium))
                        Text(feature.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        }
    }

    // MARK: - Products

    @ViewBuilder
    private var productsSection: some View {
        VStack(spacing: 12) {
            if subscriptionManager.isLoading && subscriptionManager.products.isEmpty {
                ProgressView()
                    .padding(.vertical, 40)
            } else if subscriptionManager.products.isEmpty {
                Text("Unable to load products")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 40)

                Button("Retry") {
                    Task { await subscriptionManager.loadProducts() }
                }
            } else {
                ForEach(subscriptionManager.products, id: \.id) { product in
                    ProductCard(
                        product: product,
                        isSelected: selectedProduct?.id == product.id
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedProduct = product
                        }
                    }
                }
            }
        }
    }

    // MARK: - Purchase Button

    @ViewBuilder
    private var purchaseButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            HStack {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(purchaseButtonTitle)
                        .font(.roundedHeadline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(selectedProduct == nil || isPurchasing)
    }

    private var purchaseButtonTitle: String {
        guard let product = selectedProduct else { return "Select a Plan" }

        if product.id == ProductID.lifetime.rawValue {
            return "Purchase for \(product.displayPrice)"
        } else if product.id == ProductID.yearly.rawValue {
            return "Subscribe for \(product.displayPrice)/year"
        } else {
            return "Subscribe for \(product.displayPrice)/month"
        }
    }

    // MARK: - Legal

    @ViewBuilder
    private var legalSection: some View {
        VStack(spacing: 8) {
            Text("Subscriptions automatically renew unless cancelled at least 24 hours before the end of the current period. You can manage subscriptions in your Apple ID settings.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Use", destination: URL(string: "https://apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy Policy", destination: URL(string: "https://apple.com/legal/privacy/")!)
            }
            .font(.caption2)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func purchase() async {
        guard let product = selectedProduct else { return }

        isPurchasing = true
        HapticManager.shared.click()

        do {
            _ = try await subscriptionManager.purchase(product)
            HapticManager.shared.success()
            dismiss()
        } catch PurchaseError.purchaseCancelled {
            // User cancelled, no error needed
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            HapticManager.shared.error()
        }

        isPurchasing = false
    }

    private func restorePurchases() async {
        isPurchasing = true

        do {
            try await subscriptionManager.restorePurchases()

            if subscriptionManager.isPremium {
                HapticManager.shared.success()
                dismiss()
            } else {
                errorMessage = "No previous purchases found"
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isPurchasing = false
    }
}

// MARK: - Product Card

private struct ProductCard: View {
    let product: Product
    let isSelected: Bool
    let onSelect: () -> Void

    private var isLifetime: Bool {
        product.id == ProductID.lifetime.rawValue
    }

    private var isYearly: Bool {
        product.id == ProductID.yearly.rawValue
    }

    private var savingsText: String? {
        if isYearly {
            return "Save 44%"
        } else if isLifetime {
            return "Best Value"
        }
        return nil
    }

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(.roundedHeadline)

                        if let savings = savingsText {
                            Text(savings)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }

                    Text(priceDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .orange : .secondary)
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var priceDescription: String {
        if isLifetime {
            return "\(product.displayPrice) one-time purchase"
        } else if isYearly {
            return "\(product.displayPrice)/year"
        } else {
            return "\(product.displayPrice)/month"
        }
    }
}

// MARK: - Preview

#Preview {
    PaywallView(trigger: .settings)
}
