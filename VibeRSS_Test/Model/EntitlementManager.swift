import Foundation

// MARK: - Entitlement Manager

@MainActor
final class EntitlementManager {
    static let shared = EntitlementManager()

    private var subscriptionManager: SubscriptionManager { .shared }

    private init() {}

    // MARK: - Feature Limits

    struct Limits {
        // At-a-Glance
        static let freeAtAGlanceCount = 1
        static let premiumAtAGlanceCount = 4

        // Feeds/Sources
        static let freeFeedLimit = 5
        static let premiumFeedLimit = Int.max

        // News Reel swipes per day
        static let freeSwipesPerDay = 10
        static let premiumSwipesPerDay = Int.max

        // Saved Articles
        static let freeSavedArticles = 10
        static let premiumSavedArticles = Int.max
    }

    // MARK: - Premium Status

    var isPremium: Bool {
        subscriptionManager.isPremium
    }

    // MARK: - At-a-Glance

    var atAGlanceLimit: Int {
        isPremium ? Limits.premiumAtAGlanceCount : Limits.freeAtAGlanceCount
    }

    // MARK: - Feeds/Sources

    var feedLimit: Int {
        isPremium ? Limits.premiumFeedLimit : Limits.freeFeedLimit
    }

    func canAddFeed(currentCount: Int) -> Bool {
        isPremium || currentCount < Limits.freeFeedLimit
    }

    var remainingFeedSlots: Int {
        guard !isPremium else { return Int.max }
        return max(0, Limits.freeFeedLimit - currentFeedCount)
    }

    private var currentFeedCount: Int {
        // This will be set by callers when checking
        0
    }

    // MARK: - News Reel

    var dailySwipeLimit: Int {
        isPremium ? Limits.premiumSwipesPerDay : Limits.freeSwipesPerDay
    }

    // MARK: - Saved Articles

    var savedArticlesLimit: Int {
        isPremium ? Limits.premiumSavedArticles : Limits.freeSavedArticles
    }

    func canSaveArticle(currentCount: Int) -> Bool {
        isPremium || currentCount < Limits.freeSavedArticles
    }

    // MARK: - Feature Descriptions (for paywall)

    static let premiumFeatures: [(icon: String, title: String, description: String)] = [
        ("sparkles", "At-a-Glance", "See up to 4 articles with AI summaries"),
        ("antenna.radiowaves.left.and.right", "Unlimited Sources", "Subscribe to as many RSS feeds as you want"),
        ("rectangle.stack", "Unlimited News Reel", "Swipe through articles without daily limits"),
        ("heart.fill", "Unlimited Saved Articles", "Save as many articles as you need")
    ]

    static let freeFeatureLimits: [String] = [
        "1 article in At-a-Glance",
        "5 sources maximum",
        "10 News Reel swipes per day",
        "10 saved articles maximum"
    ]
}
