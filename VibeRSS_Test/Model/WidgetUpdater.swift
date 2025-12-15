//
//  WidgetUpdater.swift
//  Helper to update widget data from main app
//

import Foundation
import WidgetKit
import os.log

private let widgetLogger = Logger(subsystem: "IDKN.TodayRSS", category: "WidgetUpdater")

@MainActor
class WidgetUpdater {
    static let shared = WidgetUpdater()

    private var debounceTask: Task<Void, Never>?
    private var installedWidgetKinds: Set<String> = []
    private var lastWidgetCheck: Date = .distantPast

    /// Check which widgets are currently installed and cache the result
    private func refreshInstalledWidgets() async {
        // Only check every 30 seconds to avoid excessive calls
        guard Date().timeIntervalSince(lastWidgetCheck) > 30 else { return }
        lastWidgetCheck = Date()

        do {
            let configurations = try await WidgetCenter.shared.currentConfigurations()
            installedWidgetKinds = Set(configurations.map { $0.kind })
            widgetLogger.info("📱 Installed widgets: \(self.installedWidgetKinds.joined(separator: ", "))")
        } catch {
            widgetLogger.error("❌ Failed to get widget configurations: \(error.localizedDescription)")
            // Assume both widgets might be installed if we can't check
            installedWidgetKinds = ["SmallRSSWidget", "MediumRSSWidget"]
        }
    }

    /// Reload timelines only for widgets that are actually installed
    private func reloadInstalledWidgets() {
        if installedWidgetKinds.isEmpty {
            // If we haven't checked yet, reload both (safe fallback)
            widgetLogger.info("🔄 Reloading all widget timelines (no cache)")
            WidgetCenter.shared.reloadTimelines(ofKind: "SmallRSSWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "MediumRSSWidget")
        } else {
            for kind in installedWidgetKinds {
                widgetLogger.info("🔄 Reloading timeline for: \(kind)")
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
        }
    }

    /// Update widget source config (feeds & folders list)
    /// Call this when feeds or folders change
    func updateSourceConfig(feeds: [Feed], folders: [Folder]) {
        // Convert to widget-compatible format
        let widgetFeeds = feeds.map { feed in
            WidgetFeed(
                id: feed.id.uuidString,
                title: feed.title,
                url: feed.url.absoluteString,
                iconURL: feed.iconURL?.absoluteString,
                folderID: feed.folderID?.uuidString
            )
        }

        let widgetFolders = folders.map { folder in
            WidgetFolder(
                id: folder.id.uuidString,
                name: folder.name
            )
        }

        let config = WidgetSourceConfig(
            feeds: widgetFeeds,
            folders: widgetFolders,
            lastUpdated: Date()
        )

        // Save to App Group
        WidgetDataManager.shared.saveSourceConfig(config)
        widgetLogger.info("💾 Saved widget config: \(feeds.count) feeds, \(folders.count) folders")

        // Refresh widget cache and reload timelines
        Task {
            await refreshInstalledWidgets()
            reloadInstalledWidgets()
        }

        // Invalidate configuration recommendations so new sources appear in widget picker
        WidgetCenter.shared.invalidateConfigurationRecommendations()
    }

    /// Update cached articles for widgets
    /// Call this after fetching articles from feeds
    func updateArticles(articlesByFeed: [UUID: [FeedItem]]) {
        // Debounce to avoid excessive updates
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }

            // Load existing articles and merge (don't wipe feeds that failed to load)
            var widgetArticles = WidgetDataManager.shared.loadArticles()

            for (feedID, articles) in articlesByFeed {
                // Sort by date (newest first) before taking top 10
                let sorted = articles.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
                let converted = sorted.prefix(10).map { article in
                    WidgetArticle(
                        id: article.id.uuidString,
                        title: article.title,
                        link: article.link.absoluteString,
                        summary: article.summary,
                        pubDate: article.pubDate,
                        thumbnailURL: article.thumbnailURL?.absoluteString,
                        sourceTitle: article.sourceTitle,
                        sourceIconURL: article.sourceIconURL?.absoluteString
                    )
                }
                widgetArticles[feedID.uuidString] = Array(converted)
            }

            // Save merged articles to App Group
            WidgetDataManager.shared.saveArticles(widgetArticles)
            widgetLogger.info("💾 Saved \(articlesByFeed.count) feeds to widget storage (debounced)")

            // Refresh widget cache and reload timelines
            await refreshInstalledWidgets()
            reloadInstalledWidgets()
        }
    }

    /// Quick update just to refresh timelines
    func reloadTimelines() {
        widgetLogger.info("🔄 Manual timeline reload requested")
        Task {
            await refreshInstalledWidgets()
            reloadInstalledWidgets()
        }
    }

    /// Update articles immediately without debounce (for background sync)
    func updateArticlesImmediately(articlesByFeed: [UUID: [FeedItem]]) async {
        // Load existing articles and merge (don't wipe feeds that failed to load)
        var widgetArticles = WidgetDataManager.shared.loadArticles()

        for (feedID, articles) in articlesByFeed {
            // Sort by date (newest first) before taking top 10
            let sorted = articles.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            let converted = sorted.prefix(10).map { article in
                WidgetArticle(
                    id: article.id.uuidString,
                    title: article.title,
                    link: article.link.absoluteString,
                    summary: article.summary,
                    pubDate: article.pubDate,
                    thumbnailURL: article.thumbnailURL?.absoluteString,
                    sourceTitle: article.sourceTitle,
                    sourceIconURL: article.sourceIconURL?.absoluteString
                )
            }
            widgetArticles[feedID.uuidString] = Array(converted)
        }

        // Save merged articles to App Group immediately (no debounce)
        WidgetDataManager.shared.saveArticles(widgetArticles)
        widgetLogger.info("💾 Saved \(articlesByFeed.count) feeds to widget storage (immediate)")

        // Refresh widget cache and reload timelines
        await refreshInstalledWidgets()
        reloadInstalledWidgets()
    }

    /// Sync a single feed's articles to widgets (with thumbnail caching)
    /// Call this when user browses/refreshes a feed
    func syncFeedToWidget(feedID: UUID, articles: [FeedItem]) {
        Task {
            // Sort by date and download thumbnails for top 5 newest articles
            let sorted = articles.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            await downloadImagesForArticles(Array(sorted.prefix(5)))

            // Update widget storage (uses debouncing)
            updateArticles(articlesByFeed: [feedID: articles])
        }
    }

    /// Sync multiple feeds to widgets (with thumbnail caching)
    /// Call this when user browses folders or all articles
    func syncFeedsToWidget(articlesByFeed: [UUID: [FeedItem]]) {
        Task {
            // Download thumbnails and favicons for top 5 newest articles from each feed
            var allArticles: [FeedItem] = []
            for (_, articles) in articlesByFeed {
                let sorted = articles.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
                allArticles.append(contentsOf: sorted.prefix(5))
            }
            await downloadImagesForArticles(allArticles)

            // Update widget storage (uses debouncing)
            updateArticles(articlesByFeed: articlesByFeed)
        }
    }

    /// Download thumbnails and favicons for articles
    private func downloadImagesForArticles(_ articles: [FeedItem]) async {
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

        // Download in parallel
        await withTaskGroup(of: Void.self) { group in
            for url in thumbnailURLs.prefix(20) {
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
    }
}
