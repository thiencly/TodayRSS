import SwiftUI

// MARK: - Subscription Status View

struct SubscriptionStatusView: View {
    @Binding var showingPaywall: Bool
    @State private var isRestoring = false

    private var subscriptionManager: SubscriptionManager { .shared }

    var body: some View {
        Section {
            if SubscriptionManager.shared.isPremium {
                premiumActiveRow
                subscriptionDetailsRow
                manageSubscriptionButton
            } else {
                upgradeRow
                restoreRow
                currentLimitsRow
            }
        } header: {
            Text("Subscription")
        }
    }

    // MARK: - Premium Active

    @ViewBuilder
    private var premiumActiveRow: some View {
        HStack {
            Label {
                Text("Premium Active")
            } icon: {
                Image(systemName: "star.fill")
                    .foregroundStyle(.orange)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var subscriptionDetailsRow: some View {
        switch subscriptionManager.subscriptionStatus {
        case .lifetime:
            HStack {
                Text("Plan")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Lifetime")
            }
            .font(.subheadline)

        case .subscribed(let expiryDate, let willRenew):
            if let date = expiryDate {
                HStack {
                    Text(willRenew ? "Renews" : "Expires")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(date, style: .date)
                }
                .font(.subheadline)
            }

        case .notSubscribed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var manageSubscriptionButton: some View {
        Button {
            openManageSubscriptions()
        } label: {
            HStack {
                Text("Manage Subscription")
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Free User

    @ViewBuilder
    private var upgradeRow: some View {
        Button {
            showingPaywall = true
        } label: {
            HStack {
                Label {
                    Text("Upgrade to Premium")
                } icon: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.orange)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var restoreRow: some View {
        Button {
            Task { await restorePurchases() }
        } label: {
            HStack {
                if isRestoring {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Restoring...")
                } else {
                    Text("Restore Purchases")
                }
            }
        }
        .disabled(isRestoring)
    }

    @ViewBuilder
    private var currentLimitsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Free Plan Limits")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(EntitlementManager.freeFeatureLimits, id: \.self) { limit in
                HStack(spacing: 4) {
                    Image(systemName: "minus")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(limit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func openManageSubscriptions() {
        if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }

    private func restorePurchases() async {
        isRestoring = true

        do {
            try await subscriptionManager.restorePurchases()
            if subscriptionManager.isPremium {
                HapticManager.shared.success()
            }
        } catch {
            print("Restore failed: \(error)")
        }

        isRestoring = false
    }
}

// MARK: - Preview

#Preview {
    List {
        SubscriptionStatusView(showingPaywall: .constant(false))
    }
}
