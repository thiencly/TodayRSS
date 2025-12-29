import SwiftUI
import Combine
import Reeeed

@MainActor
final class FolderItemsViewModel: ObservableObject {
    @Published var items: [Article] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var newArticleIDs: Set<UUID> = []

    private let service = FeedService()
    private var previousArticleIDs: Set<UUID> = []
    private var lastLoadedArticlesByFeed: [UUID: [FeedItem]] = [:]

    private func updateNewArticles(from articles: [Article]) {
        let currentIDs = Set(articles.map { $0.id })
        if previousArticleIDs.isEmpty {
            newArticleIDs = []
        } else {
            newArticleIDs = currentIDs.subtracting(previousArticleIDs)
        }
        previousArticleIDs = currentIDs
    }

    func load(for folder: Folder, feeds: [Feed]) async {
        isLoading = true
        errorMessage = nil
        let sources = feeds.filter { $0.folderID == folder.id }
        var all: [Article] = []
        var hasCachedData = false

        // Try to load from cache first (instant)
        for src in sources {
            if let cachedItems = await FeedItemsCache.shared.getFeedItems(
                for: src.id,
                sourceID: src.id,
                sourceTitle: src.title,
                sourceIconURL: src.iconURL
            ) {
                all.append(contentsOf: cachedItems)
                hasCachedData = true
            }
        }

        if hasCachedData && !all.isEmpty {
            let sorted = all.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            updateNewArticles(from: sorted)
            items = sorted
            isLoading = false

            // Cache articles for offline reading in the background
            Task { await cacheArticlesForOffline(sorted) }
            return
        }

        // Fallback to network fetch if no cache
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
        updateNewArticles(from: sorted)
        items = sorted
        isLoading = false

        // Cache articles for offline reading in the background
        Task { await cacheArticlesForOffline(sorted) }
    }

    func loadAll(feeds: [Feed]) async {
        isLoading = true
        errorMessage = nil
        let sources = feeds
        var all: [Article] = []
        var hasCachedData = false

        // Try to load from cache first (instant)
        for src in sources {
            if let cachedItems = await FeedItemsCache.shared.getFeedItems(
                for: src.id,
                sourceID: src.id,
                sourceTitle: src.title,
                sourceIconURL: src.iconURL
            ) {
                all.append(contentsOf: cachedItems)
                hasCachedData = true
            }
        }

        if hasCachedData && !all.isEmpty {
            // Filter to only show articles from today
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            let filtered = all.filter { article in
                guard let pubDate = article.pubDate else { return false }
                return pubDate >= startOfToday
            }
            let sorted = filtered.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            updateNewArticles(from: sorted)
            items = sorted
            isLoading = false

            // Cache articles for offline reading in the background
            Task { await cacheArticlesForOffline(sorted) }
            return
        }

        // Fallback to network fetch if no cache
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
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let filtered = all.filter { article in
            guard let pubDate = article.pubDate else { return false }
            return pubDate >= startOfToday
        }
        let sorted = filtered.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        updateNewArticles(from: sorted)
        items = sorted
        isLoading = false

        // Cache articles for offline reading in the background
        Task { await cacheArticlesForOffline(sorted) }
    }

    /// Cache articles for offline reading when user opens a folder/topic
    /// Caches full styled HTML for the best offline experience
    private func cacheArticlesForOffline(_ articles: [Article]) async {
        let offlineCachingEnabled = UserDefaults.standard.object(forKey: "offlineCachingEnabled") as? Bool ?? true
        guard offlineCachingEnabled else { return }

        // Cache top 20 articles from this folder/topic
        let articlesToCache = Array(articles.prefix(20))

        for article in articlesToCache {
            // Skip if already cached (check HTML cache)
            if await ArticleContentCache.shared.cachedContent(for: article.link) != nil {
                continue
            }

            do {
                // Fetch and extract full styled HTML using Reeeed
                let result = try await Reeeed.fetchAndExtractContent(fromURL: article.link)

                // Cache the styled HTML
                let cached = CachedArticleContent(
                    styledHTML: result.styledHTML,
                    baseURL: result.baseURL,
                    title: result.extracted.title,
                    timestamp: Date()
                )
                await ArticleContentCache.shared.storeContent(cached, for: article.link)
            } catch {
                // Silently continue - offline caching is best effort
            }
        }
    }
}
