//
//  BackgroundSyncManager.swift
//  VibeRSS_Test
//
//  Background sync manager using BGTaskScheduler following Apple's guidelines.
//  Handles periodic RSS feed syncing and widget updates.
//

import Foundation
import BackgroundTasks
import WidgetKit
import Observation
import Reeeed
import UIKit

@MainActor
@Observable
final class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()

    // Background task identifiers
    static nonisolated let refreshTaskIdentifier = "IDKN.TodayRSS.refresh"

    // Sync interval options (in minutes)
    enum SyncInterval: Int, CaseIterable, Codable, Sendable {
        case minutes15 = 15
        case minutes30 = 30
        case hourly = 60
        case hours2 = 120
        case hours4 = 240
        case manual = 0

        var displayName: String {
            switch self {
            case .minutes15: return "Every 15 minutes"
            case .minutes30: return "Every 30 minutes"
            case .hourly: return "Every hour"
            case .hours2: return "Every 2 hours"
            case .hours4: return "Every 4 hours"
            case .manual: return "Manual only"
            }
        }

        var timeInterval: TimeInterval? {
            guard self != .manual else { return nil }
            return TimeInterval(rawValue * 60)
        }
    }

    var syncInterval: SyncInterval {
        didSet {
            saveSyncInterval()
            scheduleBackgroundRefresh()
        }
    }

    var lastSyncDate: Date?
    var isSyncing = false

    private let syncIntervalKey = "backgroundSyncInterval"
    private let lastSyncKey = "lastBackgroundSyncDate"

    private init() {
        // Load saved settings
        if let savedInterval = UserDefaults.standard.object(forKey: syncIntervalKey) as? Int,
           let interval = SyncInterval(rawValue: savedInterval) {
            self.syncInterval = interval
        } else {
            self.syncInterval = .hourly // Default to hourly
        }

        if let lastSync = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            self.lastSyncDate = lastSync
        }

        // Sync interval to App Group for widget access
        if let sharedDefaults = UserDefaults(suiteName: "group.IDKN.TodayRSS") {
            sharedDefaults.set(syncInterval.rawValue, forKey: "widgetRefreshInterval")
        }
    }

    // MARK: - Task Registration

    /// Call this in application(_:didFinishLaunchingWithOptions:) or App.init
    nonisolated func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { task in
            Task { @MainActor in
                await self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
            }
        }
    }

    // MARK: - Background Task Scheduling

    func scheduleBackgroundRefresh() {
        // Cancel any existing scheduled tasks
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskIdentifier)

        guard let interval = syncInterval.timeInterval else {
            // Manual mode - don't schedule background task
            // But still schedule a minimal refresh to keep widget data fresh
            scheduleMinimalBackgroundRefresh()
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        // Set earliest begin date based on sync interval
        // Apple recommends at least 15 minutes
        request.earliestBeginDate = Date(timeIntervalSinceNow: max(interval, 15 * 60))

        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background refresh scheduled for \(syncInterval.displayName)")
        } catch {
            print("Failed to schedule background refresh: \(error)")
        }
    }

    /// Schedule a minimal background refresh even in manual mode
    /// This helps keep widget timelines populated
    private func scheduleMinimalBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        // Schedule for 4 hours from now - just to ensure widget doesn't go completely stale
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("Minimal background refresh scheduled (4 hours)")
        } catch {
            print("Failed to schedule minimal background refresh: \(error)")
        }
    }

    // MARK: - Background Task Handling

    private func handleBackgroundRefresh(task: BGAppRefreshTask) async {
        // Schedule the next refresh
        scheduleBackgroundRefresh()

        // Create a task to perform the sync
        let syncTask = Task {
            await performSync()
        }

        // Set expiration handler
        task.expirationHandler = {
            syncTask.cancel()
        }

        // Wait for sync to complete
        await syncTask.value

        // Mark task as completed
        task.setTaskCompleted(success: !syncTask.isCancelled)
    }

    // MARK: - Sync Logic

    // Widget storage limits
    private let maxArticlesPerFeedForWidget = 5
    private let maxTotalWidgetArticles = 20

    /// Perform a full sync of all feeds
    func performSync() async {
        guard !isSyncing else { return }

        isSyncing = true

        defer {
            isSyncing = false
        }

        // Load feeds from UserDefaults (same as FeedStore)
        let feeds = loadFeeds()
        let folders = loadFolders()

        // Always sync source config to widget (ensures widget knows about feeds)
        WidgetUpdater.shared.updateSourceConfig(feeds: feeds, folders: folders)

        guard !feeds.isEmpty else { return }

        // Get widget sync info - which feeds do widgets need?
        let widgetInfo = await getWidgetSyncInfo(allFeeds: feeds, allFolders: folders)

        // Determine articles per feed:
        // - Widget feeds: 5 articles (for widget display)
        // - Non-widget feeds: 1 article (for At a Glance only)
        // - All feeds if "All Sources" widget or no widgets
        let widgetFeedIDs: Set<UUID> = widgetInfo.feedIDsToSync ?? Set(feeds.map { $0.id })

        if widgetInfo.hasWidgets {
            if widgetInfo.hasAllSourcesWidget {
                print("Background sync: All Sources widget - 5 articles per feed")
            } else {
                print("Background sync: Widget feeds (\(widgetFeedIDs.count)) get 5 articles, others get 1 for At a Glance")
            }
        } else {
            print("Background sync: No widgets - 1 article per feed for At a Glance")
        }

        let feedService = FeedService()
        var articlesByFeed: [UUID: [FeedItem]] = [:]

        // Fetch articles from ALL feeds concurrently
        // Widget feeds get 5 articles, non-widget feeds get 1 (for At a Glance)
        await withTaskGroup(of: (UUID, [FeedItem])?.self) { group in
            for feed in feeds {
                let isWidgetFeed = widgetFeedIDs.contains(feed.id)
                let articlesPerFeed = (widgetInfo.hasWidgets && isWidgetFeed) ? 5 : 1

                group.addTask {
                    do {
                        var items = try await feedService.loadItems(from: feed.url)
                        // Add source info
                        for i in items.indices {
                            items[i].sourceID = feed.id
                            items[i].sourceTitle = feed.title
                            items[i].sourceIconURL = feed.iconURL
                        }
                        // Sort by date and take only what we need
                        items.sort { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }

                        // Keep only recent items based on user's cache retention setting
                        let retentionDays = UserDefaults.standard.integer(forKey: "cacheRetentionDays")
                        let days = retentionDays > 0 ? retentionDays : 7 // Default to 7 days
                        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
                        items = items.filter { item in
                            if let d = item.pubDate { return d >= cutoff } else { return true }
                        }
                        return (feed.id, Array(items.prefix(articlesPerFeed)))
                    } catch {
                        print("Failed to fetch feed \(feed.title): \(error)")
                        return nil
                    }
                }
            }

            for await result in group {
                if let (feedID, items) = result {
                    articlesByFeed[feedID] = items
                }
            }
        }

        // Widget sync: Only if widgets are installed
        if widgetInfo.hasWidgets && !articlesByFeed.isEmpty {
            // Prepare limited articles for widget (only widget-configured feeds)
            var widgetArticlesByFeed: [UUID: [FeedItem]] = [:]
            var allWidgetArticles: [FeedItem] = []

            for (feedID, articles) in articlesByFeed {
                // Only include feeds that widgets are configured to show
                guard widgetFeedIDs.contains(feedID) else { continue }

                let sorted = articles.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
                let limited = Array(sorted.prefix(maxArticlesPerFeedForWidget))
                widgetArticlesByFeed[feedID] = limited
                allWidgetArticles.append(contentsOf: limited)
            }

            // Sort all and cap at total limit
            allWidgetArticles.sort { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            let cappedArticles = Array(allWidgetArticles.prefix(maxTotalWidgetArticles))

            // Save to widget storage
            await WidgetUpdater.shared.updateArticlesImmediately(articlesByFeed: widgetArticlesByFeed)

            // Download thumbnails for widget articles (within background time budget)
            await downloadWidgetThumbnails(articles: cappedArticles)

            print("Widget sync: \(widgetArticlesByFeed.count) feeds, \(cappedArticles.count) articles with thumbnails")
        }

        // Pre-fetch newest articles for At a Glance summaries
        await prefetchArticleContent(articlesByFeed: articlesByFeed)

        // Purge expired cached articles based on retention setting
        let retentionDays = UserDefaults.standard.integer(forKey: "cacheRetentionDays")
        let days = retentionDays > 0 ? retentionDays : 7
        await ArticleTextCache.shared.purgeExpiredEntries(retentionDays: days)

        // Update last sync date
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)

        // Reload widget timelines AFTER thumbnails are downloaded
        if widgetInfo.hasWidgets {
            WidgetCenter.shared.reloadTimelines(ofKind: "SmallRSSWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "MediumRSSWidget")
        }

        // Notify that sync completed (so At a Glance can refresh with cached data)
        NotificationCenter.default.post(name: .backgroundSyncCompleted, object: nil)

        print("Sync completed: \(articlesByFeed.count) feeds, \(articlesByFeed.values.flatMap { $0 }.count) articles")
    }

    /// Pre-fetch only the globally newest articles for At a Glance summaries
    /// At a Glance shows max 4 articles, so we only cache the 4-6 newest globally
    private func prefetchArticleContent(articlesByFeed: [UUID: [FeedItem]]) async {
        // Check if offline caching is enabled (default: enabled)
        let offlineCachingEnabled = UserDefaults.standard.object(forKey: "offlineCachingEnabled") as? Bool ?? true
        guard offlineCachingEnabled else { return }

        // Get ALL newest articles, then take the globally newest 6
        // (At a Glance shows max 4, but cache a couple extra as buffer)
        let allNewestArticles = articlesByFeed.values
            .compactMap { articles in
                articles.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }.first
            }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            .prefix(6) // Only the 6 globally newest

        guard !allNewestArticles.isEmpty else { return }

        // Filter out already cached articles
        var uncachedArticles: [FeedItem] = []
        for article in allNewestArticles {
            if await !ArticleTextCache.shared.isCached(url: article.link) {
                uncachedArticles.append(article)
            }
        }

        guard !uncachedArticles.isEmpty else {
            print("All At a Glance articles already cached")
            return
        }

        var cachedCount = 0

        // Fetch concurrently (max 6 articles, very fast)
        await withTaskGroup(of: Bool.self) { group in
            for article in uncachedArticles {
                group.addTask {
                    do {
                        let html = try await ArticleSummarizer.shared.fetchHTML(url: article.link)
                        let text = ArticleSummarizer.shared.extractReadableText(from: String(html.prefix(100_000)))

                        if !text.isEmpty {
                            await ArticleTextCache.shared.storeText(
                                text,
                                for: article.link,
                                title: article.title,
                                sourceTitle: article.sourceTitle,
                                pubDate: article.pubDate
                            )
                            return true
                        }
                        return false
                    } catch {
                        return false
                    }
                }
            }

            for await success in group {
                if success { cachedCount += 1 }
            }
        }

        if cachedCount > 0 {
            print("Background: Cached \(cachedCount) articles for At a Glance")
        }
    }

    // MARK: - Helper Methods

    private func loadFeeds() -> [Feed] {
        guard let data = UserDefaults.standard.data(forKey: "viberss.feeds") else { return [] }
        do {
            return try JSONDecoder().decode([Feed].self, from: data)
        } catch {
            print("Failed to load feeds: \(error)")
            return []
        }
    }

    private func loadFolders() -> [Folder] {
        guard let data = UserDefaults.standard.data(forKey: "viberss.folders") else { return [] }
        do {
            return try JSONDecoder().decode([Folder].self, from: data)
        } catch {
            print("Failed to load folders: \(error)")
            return []
        }
    }

    /// Widget sync result containing which feeds to sync and whether widgets exist
    private struct WidgetSyncInfo {
        let hasWidgets: Bool
        let feedIDsToSync: Set<UUID>?  // nil means sync all feeds, empty means none
        let hasAllSourcesWidget: Bool
    }

    /// Get information about installed widgets and which feeds they need
    private func getWidgetSyncInfo(allFeeds: [Feed], allFolders: [Folder]) async -> WidgetSyncInfo {
        // Read widget configurations from App Group (set by widget when configured)
        guard let sharedDefaults = UserDefaults(suiteName: "group.IDKN.TodayRSS") else {
            return WidgetSyncInfo(hasWidgets: false, feedIDsToSync: Set(), hasAllSourcesWidget: false)
        }

        // Check if widgets are installed
        do {
            let configurations = try await WidgetCenter.shared.currentConfigurations()
            guard !configurations.isEmpty else {
                return WidgetSyncInfo(hasWidgets: false, feedIDsToSync: Set(), hasAllSourcesWidget: false)
            }
        } catch {
            // On error, assume no widgets
            return WidgetSyncInfo(hasWidgets: false, feedIDsToSync: Set(), hasAllSourcesWidget: false)
        }

        // Read configured source IDs from App Group
        // Widget saves these when user configures it
        let configuredSourceIDs = sharedDefaults.stringArray(forKey: "widgetConfiguredSourceIDs") ?? []

        // If no specific sources configured, widgets use "All Sources"
        if configuredSourceIDs.isEmpty {
            return WidgetSyncInfo(hasWidgets: true, feedIDsToSync: nil, hasAllSourcesWidget: true)
        }

        // Determine which feeds are needed
        var neededFeedIDs = Set<UUID>()
        var hasAllSources = false

        for sourceID in configuredSourceIDs {
            if sourceID == "all" {
                hasAllSources = true
                continue
            }

            let normalizedID = sourceID.uppercased()

            // Check if it's a feed
            if let feed = allFeeds.first(where: { $0.id.uuidString.uppercased() == normalizedID }) {
                neededFeedIDs.insert(feed.id)
                continue
            }

            // Check if it's a folder - add all feeds in that folder
            if let folderUUID = UUID(uuidString: sourceID),
               allFolders.contains(where: { $0.id == folderUUID }) {
                let folderFeeds = allFeeds.filter { $0.folderID == folderUUID }
                for feed in folderFeeds {
                    neededFeedIDs.insert(feed.id)
                }
            }
        }

        // If any widget uses "All Sources", sync all
        if hasAllSources {
            return WidgetSyncInfo(hasWidgets: true, feedIDsToSync: nil, hasAllSourcesWidget: true)
        }

        return WidgetSyncInfo(hasWidgets: true, feedIDsToSync: neededFeedIDs, hasAllSourcesWidget: false)
    }

    /// Download thumbnails and favicons for widget articles
    private func downloadWidgetThumbnails(articles: [FeedItem]) async {
        var thumbnailURLs: [URL] = []
        var faviconURLs: Set<URL> = []

        for article in articles {
            if let url = article.thumbnailURL {
                thumbnailURLs.append(url)
            }
            if let iconURL = article.sourceIconURL {
                faviconURLs.insert(iconURL)
            }
        }

        guard !thumbnailURLs.isEmpty || !faviconURLs.isEmpty else { return }

        // Download in parallel
        await withTaskGroup(of: Void.self) { group in
            for url in thumbnailURLs {
                group.addTask {
                    _ = await WidgetImageCache.shared.downloadAndCache(from: url)
                }
            }
            for url in faviconURLs {
                group.addTask {
                    _ = await WidgetImageCache.shared.downloadAndCache(from: url)
                }
            }
        }

        print("Background sync: Downloaded \(thumbnailURLs.count) thumbnails, \(faviconURLs.count) favicons")
    }

    private func saveSyncInterval() {
        UserDefaults.standard.set(syncInterval.rawValue, forKey: syncIntervalKey)
        // Also save to App Group so widget can read it
        if let sharedDefaults = UserDefaults(suiteName: "group.IDKN.TodayRSS") {
            sharedDefaults.set(syncInterval.rawValue, forKey: "widgetRefreshInterval")
        }
    }

    // MARK: - Manual Sync

    /// Trigger a manual sync (can be called from UI)
    func syncNow() async {
        await performSync()
    }

    // MARK: - Scene Phase Handlers

    /// Call when app enters background
    func handleEnterBackground() {
        scheduleBackgroundRefresh()
    }

    /// Call when app becomes active - sync if needed
    func handleBecomeActive() async {
        // Purge expired cached articles on app launch
        let retentionDays = UserDefaults.standard.integer(forKey: "cacheRetentionDays")
        let days = retentionDays > 0 ? retentionDays : 7
        await ArticleTextCache.shared.purgeExpiredEntries(retentionDays: days)

        // Always sync on app launch if never synced before
        guard let lastSync = lastSyncDate else {
            await performSync()
            return
        }

        // If manual mode, just reload widget timelines (use cached data)
        guard let interval = syncInterval.timeInterval else {
            WidgetCenter.shared.reloadTimelines(ofKind: "SmallRSSWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "MediumRSSWidget")
            return
        }

        // If enough time has passed since last sync, sync now
        if Date().timeIntervalSince(lastSync) > interval {
            await performSync()
        } else {
            // Even if not syncing feeds, reload widget timelines to pick up latest data
            WidgetCenter.shared.reloadTimelines(ofKind: "SmallRSSWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "MediumRSSWidget")
        }
    }
}
