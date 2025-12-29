import SwiftUI
import Combine

@MainActor
final class FolderItemsViewModel: ObservableObject {
    @Published var items: [Article] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var newArticleIDs: Set<UUID> = []

    private let service = FeedService()
    private var previousArticleIDs: Set<UUID> = []
    private var lastLoadedArticlesByFeed: [UUID: [FeedItem]] = [:]

    // Skip network refresh if cache was updated within this interval
    private let cacheFreshnessInterval: TimeInterval = 60 // 1 minute

    private func updateNewArticles(from articles: [Article]) {
        let currentIDs = Set(articles.map { $0.id })
        if previousArticleIDs.isEmpty {
            newArticleIDs = []
        } else {
            newArticleIDs = currentIDs.subtracting(previousArticleIDs)
        }
        previousArticleIDs = currentIDs
    }

    /// Check if all feeds have fresh cache
    private func allCachesAreFresh(for feedIDs: [UUID]) async -> Bool {
        for feedID in feedIDs {
            guard let lastUpdated = await FeedItemsCache.shared.getLastUpdated(for: feedID) else {
                return false
            }
            if Date().timeIntervalSince(lastUpdated) >= cacheFreshnessInterval {
                return false
            }
        }
        return true
    }

    func load(for folder: Folder, feeds: [Feed]) async {
        isLoading = true
        errorMessage = nil
        let sources = feeds.filter { $0.folderID == folder.id }
        var cachedAll: [Article] = []
        var hasCachedData = false

        // Try to load from cache first for instant display
        for src in sources {
            if let cachedItems = await FeedItemsCache.shared.getFeedItems(
                for: src.id,
                sourceID: src.id,
                sourceTitle: src.title,
                sourceIconURL: src.iconURL
            ) {
                cachedAll.append(contentsOf: cachedItems)
                hasCachedData = true
            }
        }

        // Check if all caches are fresh
        let cacheIsFresh = await allCachesAreFresh(for: sources.map { $0.id })

        if hasCachedData && !cachedAll.isEmpty {
            let sorted = cachedAll.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            // Set initial article IDs from cache (no new indicators yet)
            previousArticleIDs = Set(sorted.map { $0.id })
            items = sorted
            isLoading = false

            // Skip network refresh if cache is fresh (just fetched on app launch)
            if cacheIsFresh {
                return
            }
        }

        // Fetch from network (cache is stale or empty)
        var all: [Article] = []
        var articlesByFeed: [UUID: [FeedItem]] = [:]

        await withTaskGroup(of: (UUID, [FeedItem]).self) { group in
            for src in sources {
                group.addTask {
                    do {
                        var r = try await self.service.loadItems(from: src.url)
                        for i in r.indices {
                            r[i].sourceID = src.id
                            r[i].sourceTitle = src.title
                            r[i].sourceIconURL = src.iconURL
                        }
                        return (src.id, r)
                    } catch { return (src.id, []) }
                }
            }
            for await (feedID, result) in group {
                all.append(contentsOf: result)
                if !result.isEmpty {
                    articlesByFeed[feedID] = result
                }
            }
        }

        // Track latest articles for new indicator in sidebar
        if !articlesByFeed.isEmpty {
            lastLoadedArticlesByFeed.merge(articlesByFeed) { _, new in new }
            for (feedID, articles) in articlesByFeed {
                let urls = articles.map { $0.link }
                Task { await ArticleReadStateManager.shared.updateLatestArticles(for: feedID, urls: urls) }
            }
        }

        let sorted = all.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }

        // Update new article indicators (compares against cached articles)
        updateNewArticles(from: sorted)
        items = sorted
        isLoading = false

        // Notify sidebar to refresh if new articles were found
        if !newArticleIDs.isEmpty {
            NotificationCenter.default.post(name: .didFetchNewArticles, object: nil)
        }

        // Cache feed items for next time
        for (feedID, articles) in articlesByFeed {
            if let feed = sources.first(where: { $0.id == feedID }) {
                await FeedItemsCache.shared.storeFeedItems(
                    articles,
                    for: feedID,
                    feedTitle: feed.title,
                    feedIconURL: feed.iconURL
                )
            }
        }
    }

    func loadAll(feeds: [Feed]) async {
        isLoading = true
        errorMessage = nil
        let sources = feeds
        var cachedAll: [Article] = []
        var hasCachedData = false

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        // Try to load from cache first for instant display
        for src in sources {
            if let cachedItems = await FeedItemsCache.shared.getFeedItems(
                for: src.id,
                sourceID: src.id,
                sourceTitle: src.title,
                sourceIconURL: src.iconURL
            ) {
                cachedAll.append(contentsOf: cachedItems)
                hasCachedData = true
            }
        }

        // Check if all caches are fresh
        let cacheIsFresh = await allCachesAreFresh(for: sources.map { $0.id })

        if hasCachedData && !cachedAll.isEmpty {
            // Filter to only show articles from today
            let filtered = cachedAll.filter { article in
                guard let pubDate = article.pubDate else { return false }
                return pubDate >= startOfToday
            }
            let sorted = filtered.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            // Set initial article IDs from cache (no new indicators yet)
            previousArticleIDs = Set(sorted.map { $0.id })
            items = sorted
            isLoading = false

            // Skip network refresh if cache is fresh (just fetched on app launch)
            if cacheIsFresh {
                return
            }
        }

        // Fetch from network (cache is stale or empty)
        var all: [Article] = []
        var articlesByFeed: [UUID: [FeedItem]] = [:]

        await withTaskGroup(of: (UUID, [FeedItem]).self) { group in
            for src in sources {
                group.addTask {
                    do {
                        var r = try await self.service.loadItems(from: src.url)
                        for i in r.indices {
                            r[i].sourceID = src.id
                            r[i].sourceTitle = src.title
                            r[i].sourceIconURL = src.iconURL
                        }
                        return (src.id, r)
                    } catch { return (src.id, []) }
                }
            }
            for await (feedID, result) in group {
                all.append(contentsOf: result)
                if !result.isEmpty {
                    articlesByFeed[feedID] = result
                }
            }
        }

        if !articlesByFeed.isEmpty {
            lastLoadedArticlesByFeed.merge(articlesByFeed) { _, new in new }
        }

        // Filter to only show articles from today
        let filtered = all.filter { article in
            guard let pubDate = article.pubDate else { return false }
            return pubDate >= startOfToday
        }
        let sorted = filtered.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }

        // Update new article indicators (compares against cached articles)
        updateNewArticles(from: sorted)
        items = sorted
        isLoading = false

        // Notify sidebar to refresh if new articles were found
        if !newArticleIDs.isEmpty {
            NotificationCenter.default.post(name: .didFetchNewArticles, object: nil)
        }

        // Cache feed items for next time
        for (feedID, articles) in articlesByFeed {
            if let feed = sources.first(where: { $0.id == feedID }) {
                await FeedItemsCache.shared.storeFeedItems(
                    articles,
                    for: feedID,
                    feedTitle: feed.title,
                    feedIconURL: feed.iconURL
                )
            }
        }
    }
}
