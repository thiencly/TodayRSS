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

@MainActor
@Observable
final class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()

    // Background task identifiers
    static nonisolated let refreshTaskIdentifier = "IDKN.VibeRSS.refresh"

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
            // Manual mode - don't schedule
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

    /// Perform a full sync of all feeds
    func performSync() async {
        guard !isSyncing else { return }

        isSyncing = true

        defer {
            isSyncing = false
        }

        // Load feeds from UserDefaults (same as FeedStore)
        let feeds = loadFeeds()
        guard !feeds.isEmpty else { return }

        let feedService = FeedService()
        var articlesByFeed: [UUID: [FeedItem]] = [:]

        // Fetch articles from all feeds concurrently
        await withTaskGroup(of: (UUID, [FeedItem])?.self) { group in
            for feed in feeds {
                group.addTask {
                    do {
                        var items = try await feedService.loadItems(from: feed.url)
                        // Add source info
                        for i in items.indices {
                            items[i].sourceID = feed.id
                            items[i].sourceTitle = feed.title
                            items[i].sourceIconURL = feed.iconURL
                        }
                        // Keep only recent items (last 3 days)
                        let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
                        items = items.filter { item in
                            if let d = item.pubDate { return d >= cutoff } else { return true }
                        }
                        return (feed.id, Array(items.prefix(20)))
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

        // Pre-download thumbnails for widget (top 2 articles per feed for medium widget)
        await downloadThumbnailsForWidget(articlesByFeed: articlesByFeed)

        // Pre-cache article text for hero sources (enables fast hero summaries)
        await cacheArticleTextForHeroSources(articlesByFeed: articlesByFeed)

        // Save to widget storage
        if !articlesByFeed.isEmpty {
            WidgetUpdater.shared.updateArticles(articlesByFeed: articlesByFeed)
        }

        // Update last sync date
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)

        // Reload widget timelines
        WidgetCenter.shared.reloadAllTimelines()

        print("Background sync completed: \(articlesByFeed.count) feeds, \(articlesByFeed.values.flatMap { $0 }.count) articles")
    }

    /// Download thumbnails and favicons to shared cache for widget access
    private func downloadThumbnailsForWidget(articlesByFeed: [UUID: [FeedItem]]) async {
        // Collect thumbnail URLs to download (top 5 per feed for widget display)
        var thumbnailURLs: [URL] = []
        var faviconURLs: Set<URL> = [] // Use Set to avoid duplicates

        for (_, articles) in articlesByFeed {
            for article in articles.prefix(5) {
                if let url = article.thumbnailURL {
                    thumbnailURLs.append(url)
                }
                // Collect source favicon URLs
                if let iconURL = article.sourceIconURL {
                    faviconURLs.insert(iconURL)
                }
            }
        }

        // Download thumbnails concurrently (increased limit from 20 to 40)
        if !thumbnailURLs.isEmpty {
            await withTaskGroup(of: Void.self) { group in
                for url in thumbnailURLs.prefix(40) {
                    group.addTask {
                        _ = await WidgetImageCache.shared.downloadAndCache(from: url)
                    }
                }
            }
            print("Downloaded \(min(thumbnailURLs.count, 40)) thumbnails for widget")
        }

        // Download favicons concurrently
        if !faviconURLs.isEmpty {
            await withTaskGroup(of: Void.self) { group in
                for url in faviconURLs {
                    group.addTask {
                        _ = await WidgetImageCache.shared.downloadAndCache(from: url)
                    }
                }
            }
            print("Downloaded \(faviconURLs.count) favicons for widget")
        }
    }

    /// Pre-cache article text for hero card sources so summaries generate instantly
    private func cacheArticleTextForHeroSources(articlesByFeed: [UUID: [FeedItem]]) async {
        // Load hero source IDs (same key as ContentView)
        guard let heroData = UserDefaults.standard.data(forKey: "heroSourceIDs"),
              let heroSourceIDs = try? JSONDecoder().decode(Set<UUID>.self, from: heroData),
              !heroSourceIDs.isEmpty else {
            return
        }

        // Get latest article from each hero source
        var heroArticles: [FeedItem] = []
        for sourceID in heroSourceIDs {
            if let articles = articlesByFeed[sourceID],
               let latest = articles.sorted(by: { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }).first {
                heroArticles.append(latest)
            }
        }

        guard !heroArticles.isEmpty else { return }

        // Fetch and cache article text concurrently (limit to hero sources only)
        await withTaskGroup(of: Void.self) { group in
            for article in heroArticles {
                group.addTask {
                    // Skip if already cached
                    if await ArticleTextCache.shared.cachedText(for: article.link) != nil {
                        return
                    }

                    do {
                        let html = try await ArticleSummarizer.shared.fetchHTML(url: article.link)
                        let text = ArticleSummarizer.shared.extractReadableText(from: String(html.prefix(100_000)))
                        if !text.isEmpty {
                            await ArticleTextCache.shared.storeText(text, for: article.link)
                            print("Cached article text for hero source: \(article.sourceTitle ?? "unknown")")
                        }
                    } catch {
                        print("Failed to cache article text: \(error.localizedDescription)")
                    }
                }
            }
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

    private func saveSyncInterval() {
        UserDefaults.standard.set(syncInterval.rawValue, forKey: syncIntervalKey)
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
        guard let lastSync = lastSyncDate,
              let interval = syncInterval.timeInterval else { return }

        // If enough time has passed since last sync, sync now
        if Date().timeIntervalSince(lastSync) > interval {
            await performSync()
        }
    }
}
