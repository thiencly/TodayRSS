import Foundation

// MARK: - Usage Tracker

@MainActor
@Observable
final class UsageTracker {
    static let shared = UsageTracker()

    // MARK: - State

    private(set) var dailySwipeCount: Int = 0
    private var lastSwipeDate: Date?

    // MARK: - Persistence Keys

    private let swipeCountKey = "viberss.dailySwipeCount"
    private let lastSwipeDateKey = "viberss.lastSwipeDate"

    // MARK: - Init

    private init() {
        loadUsage()
        resetIfNewDay()
    }

    // MARK: - Swipe Tracking

    var remainingSwipes: Int {
        let limit = EntitlementManager.shared.dailySwipeLimit
        guard limit != Int.max else { return Int.max }
        return max(0, limit - dailySwipeCount)
    }

    var hasReachedSwipeLimit: Bool {
        !EntitlementManager.shared.isPremium &&
        dailySwipeCount >= EntitlementManager.Limits.freeSwipesPerDay
    }

    var swipeLimitProgress: Double {
        guard !EntitlementManager.shared.isPremium else { return 0 }
        let limit = Double(EntitlementManager.Limits.freeSwipesPerDay)
        return min(1.0, Double(dailySwipeCount) / limit)
    }

    func recordSwipe() {
        // Premium users don't need tracking
        guard !EntitlementManager.shared.isPremium else { return }

        resetIfNewDay()
        dailySwipeCount += 1
        lastSwipeDate = Date()
        saveUsage()

        print("✓ UsageTracker: Swipe \(dailySwipeCount)/\(EntitlementManager.Limits.freeSwipesPerDay)")
    }

    // MARK: - Day Reset

    private func resetIfNewDay() {
        guard let lastDate = lastSwipeDate else {
            lastSwipeDate = Date()
            return
        }

        if !Calendar.current.isDateInToday(lastDate) {
            dailySwipeCount = 0
            lastSwipeDate = Date()
            saveUsage()
            print("✓ UsageTracker: Reset swipe count for new day")
        }
    }

    // MARK: - Persistence

    private func loadUsage() {
        dailySwipeCount = UserDefaults.standard.integer(forKey: swipeCountKey)

        if let dateData = UserDefaults.standard.object(forKey: lastSwipeDateKey) as? Date {
            lastSwipeDate = dateData
        }
    }

    private func saveUsage() {
        UserDefaults.standard.set(dailySwipeCount, forKey: swipeCountKey)
        UserDefaults.standard.set(lastSwipeDate, forKey: lastSwipeDateKey)
    }

    // MARK: - Debug

    #if DEBUG
    func resetSwipeCount() {
        dailySwipeCount = 0
        lastSwipeDate = Date()
        saveUsage()
        print("⚙️ UsageTracker: Reset swipe count (debug)")
    }

    func setSwipeCount(_ count: Int) {
        dailySwipeCount = count
        lastSwipeDate = Date()
        saveUsage()
        print("⚙️ UsageTracker: Set swipe count to \(count) (debug)")
    }
    #endif
}
