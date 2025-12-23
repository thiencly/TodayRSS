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

    /// Filter articles by age based on user setting (0 = no filter)
    private func filterByAge(_ articles: [Article]) -> [Article] {
        let ageDays = UserDefaults.standard.integer(forKey: "articleAgeDays")
        guard ageDays > 0 else { return articles }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -ageDays, to: Date()) ?? Date.distantPast
        return articles.filter { article in
            guard let pubDate = article.pubDate else { return true } // Keep articles without dates
            return pubDate >= cutoffDate
        }
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

    func load(for folder: Folder, feeds: [Feed]) async {
        isLoading = true; errorMessage = nil
        let sources = feeds.filter { $0.folderID == folder.id }
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
        let filtered = filterByAge(sorted)
        updateNewArticles(from: filtered)
        items = filtered
        isLoading = false
    }

    func loadAll(feeds: [Feed]) async {
        isLoading = true; errorMessage = nil
        let sources = feeds
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
    }
}
