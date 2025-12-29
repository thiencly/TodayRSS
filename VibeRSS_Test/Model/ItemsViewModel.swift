import SwiftUI
import Combine

@MainActor
final class ItemsViewModel: ObservableObject {
    @Published var items: [Article] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var newArticleIDs: Set<UUID> = []

    private let service = FeedService()
    private var previousArticleIDs: Set<UUID> = []

    // Skip network refresh if cache was updated within this interval
    private let cacheFreshnessInterval: TimeInterval = 60 // 1 minute

    func load(for source: Source) async {
        isLoading = true
        errorMessage = nil

        // Try to load from cache first for instant display
        let cachedItems = await FeedItemsCache.shared.getFeedItems(
            for: source.id,
            sourceID: source.id,
            sourceTitle: source.title,
            sourceIconURL: source.iconURL
        )

        // Check if cache is fresh (updated within last minute)
        let lastUpdated = await FeedItemsCache.shared.getLastUpdated(for: source.id)
        let cacheIsFresh = lastUpdated.map { Date().timeIntervalSince($0) < cacheFreshnessInterval } ?? false

        if let cachedItems = cachedItems, !cachedItems.isEmpty {
            let sorted = cachedItems.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
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

            // Update new article indicators (compares against cached articles)
            updateNewArticles(from: sorted)
            items = sorted

            // Notify sidebar to refresh if new articles were found
            if !newArticleIDs.isEmpty {
                NotificationCenter.default.post(name: .didFetchNewArticles, object: nil)
            }

            // Cache the feed items for next time
            await FeedItemsCache.shared.storeFeedItems(
                sorted,
                for: source.id,
                feedTitle: source.title,
                feedIconURL: source.iconURL
            )
        } catch {
            // Only show error if we had no cached data
            if cachedItems == nil || cachedItems!.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
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
}
