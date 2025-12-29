import SwiftUI
import Combine
import Reeeed

@MainActor
final class ItemsViewModel: ObservableObject {
    @Published var items: [Article] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var newArticleIDs: Set<UUID> = []

    private let service = FeedService()
    private var previousArticleIDs: Set<UUID> = []

    func load(for source: Source) async {
        isLoading = true
        errorMessage = nil

        // Try to load from cache first (instant)
        if let cachedItems = await FeedItemsCache.shared.getFeedItems(
            for: source.id,
            sourceID: source.id,
            sourceTitle: source.title,
            sourceIconURL: source.iconURL
        ) {
            let sorted = cachedItems.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            updateNewArticles(from: sorted)
            items = sorted
            isLoading = false

            // Cache articles for offline reading in the background
            Task { await cacheArticlesForOffline(sorted) }
            return
        }

        // Fallback to network fetch if no cache
        do {
            var result = try await service.loadItems(from: source.url)
            for i in result.indices {
                result[i].sourceID = source.id
                result[i].sourceTitle = source.title
                result[i].sourceIconURL = source.iconURL
            }

            // Track latest articles for new indicator in sidebar
            let articleURLs = result.map { $0.link }
            Task { await ArticleReadStateManager.shared.updateLatestArticles(for: source.id, urls: articleURLs) }

            let sorted = result.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            updateNewArticles(from: sorted)
            items = sorted

            // Cache the feed items for next time
            await FeedItemsCache.shared.storeFeedItems(
                sorted,
                for: source.id,
                feedTitle: source.title,
                feedIconURL: source.iconURL
            )

            // Cache articles for offline reading in the background
            Task { await cacheArticlesForOffline(sorted) }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func updateNewArticles(from articles: [Article]) {
        let currentIDs = Set(articles.map { $0.id })
        if previousArticleIDs.isEmpty {
            newArticleIDs = []
        } else {
            newArticleIDs = currentIDs.subtracting(previousArticleIDs)
        }
        previousArticleIDs = currentIDs
    }

    /// Cache articles for offline reading when user opens a feed
    /// Caches full styled HTML for the best offline experience
    private func cacheArticlesForOffline(_ articles: [Article]) async {
        let offlineCachingEnabled = UserDefaults.standard.object(forKey: "offlineCachingEnabled") as? Bool ?? true
        guard offlineCachingEnabled else { return }

        // Cache top 10 articles from this feed
        let articlesToCache = Array(articles.prefix(10))

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
