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

        // Determine articles per feed for widget display
        let widgetFeedIDs: Set<UUID> = widgetInfo.feedIDsToSync ?? Set(feeds.map { $0.id })

        // Skip if no widgets installed
        guard widgetInfo.hasWidgets else {
            print("Background sync: No widgets installed, skipping")
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
            return
        }

        if widgetInfo.hasAllSourcesWidget {
            print("Background sync: All Sources widget - 5 articles per feed")
        } else {
            print("Background sync: Widget feeds (\(widgetFeedIDs.count)) - 5 articles per feed")
        }

        let feedService = FeedService()
        var articlesByFeed: [UUID: [FeedItem]] = [:]

        // Fetch articles for widget feeds
        await withTaskGroup(of: (UUID, [FeedItem])?.self) { group in
            for feed in feeds {
                // Only fetch for widget feeds
                guard widgetFeedIDs.contains(feed.id) else { continue }

                group.addTask {
                    do {
                        var items = try await feedService.loadItems(from: feed.url)
                        // Add source info
                        for i in items.indices {
                            items[i].sourceID = feed.id
                            items[i].sourceTitle = feed.title
                            items[i].sourceIconURL = feed.iconURL
                        }
                        // Sort by date
                        items.sort { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
                        // Limit to 5 per feed for widget
                        return (feed.id, Array(items.prefix(5)))
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

        // Widget sync
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

        // Update last sync date
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)

        // Reload widget timelines AFTER thumbnails are downloaded
        if widgetInfo.hasWidgets {
            WidgetCenter.shared.reloadTimelines(ofKind: "SmallRSSWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "MediumRSSWidget")
        }

        print("Background sync completed: \(articlesByFeed.count) feeds, \(articlesByFeed.values.flatMap { $0 }.count) articles")
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
            // Check for "All Sources" - widget may save as "all" or "all-sources"
            if sourceID == "all" || sourceID == "all-sources" {
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

    /// Call when app becomes active - refresh source indicators and widget sync if needed
    func handleBecomeActive() async {
        // Reload widget timelines with cached data
        WidgetCenter.shared.reloadTimelines(ofKind: "SmallRSSWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "MediumRSSWidget")

        // Refresh source list indicators (lightweight - just article lists, no content caching)
        await refreshSourceIndicators()

        // Only sync widgets if user's configured interval has passed
        guard let interval = syncInterval.timeInterval else {
            // Manual mode - no automatic widget sync
            return
        }

        let lastSync = lastSyncDate ?? .distantPast
        let timeSinceLastSync = Date().timeIntervalSince(lastSync)

        if timeSinceLastSync >= interval {
            await performSync()
        }
    }

    // MARK: - Source List Indicators

    /// Refresh all feeds to update source list indicators and cache article lists
    /// Fetches all feeds in parallel and caches them for instant display when user enters
    private func refreshSourceIndicators() async {
        let feeds = loadFeeds()
        guard !feeds.isEmpty else { return }

        let feedService = FeedService()

        // Fetch all feeds in parallel
        let results = await withTaskGroup(of: (Feed, [FeedItem])?.self) { group -> [(Feed, [FeedItem])] in
            for feed in feeds {
                group.addTask {
                    do {
                        var items = try await feedService.loadItems(from: feed.url)
                        // Add source info to each item
                        for i in items.indices {
                            items[i].sourceID = feed.id
                            items[i].sourceTitle = feed.title
                            items[i].sourceIconURL = feed.iconURL
                        }
                        return (feed, items)
                    } catch {
                        return nil
                    }
                }
            }

            var collected: [(Feed, [FeedItem])] = []
            for await result in group {
                if let r = result {
                    collected.append(r)
                }
            }
            return collected
        }

        // Update caches with fetched results
        for (feed, items) in results {
            // Update source list indicators
            let urls = items.map { $0.link }
            await ArticleReadStateManager.shared.updateLatestArticlesImmediate(for: feed.id, urls: urls)

            // Cache full article data for instant display when user enters feed
            let sorted = items.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            await FeedItemsCache.shared.storeFeedItems(
                sorted,
                for: feed.id,
                feedTitle: feed.title,
                feedIconURL: feed.iconURL
            )
        }

        // Notify sidebar to refresh
        NotificationCenter.default.post(name: .didFetchNewArticles, object: nil)
    }
}
