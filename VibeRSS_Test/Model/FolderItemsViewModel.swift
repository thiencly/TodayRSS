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
        await withTaskGroup(of: [FeedItem].self) { group in
            for src in sources {
                group.addTask {
                    do {
                        var r = try await self.service.loadItems(from: src.url)
                        for i in r.indices {
                            r[i].sourceID = src.id
                            r[i].sourceTitle = src.title
                            r[i].sourceIconURL = src.iconURL
                        }
                        return r
                    } catch { return [] }
                }
            }
            for await result in group {
                all.append(contentsOf: result)
            }
        }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()) else {
            // If date math fails, sort without filtering
            let sorted = all.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            updateNewArticles(from: sorted)
            items = sorted
            isLoading = false
            return
        }
        // Updated filter logic for pubDate nil items kept
        let filtered = all.filter { if let d = $0.pubDate { return d >= cutoff } else { return true } }
        let sorted = filtered.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        updateNewArticles(from: sorted)
        items = sorted
        isLoading = false
    }

    func loadAll(feeds: [Feed]) async {
        isLoading = true; errorMessage = nil
        let sources = feeds
        var all: [Article] = []
        await withTaskGroup(of: [FeedItem].self) { group in
            for src in sources {
                group.addTask {
                    do {
                        var r = try await self.service.loadItems(from: src.url)
                        for i in r.indices {
                            r[i].sourceID = src.id
                            r[i].sourceTitle = src.title
                            r[i].sourceIconURL = src.iconURL
                        }
                        return r
                    } catch { return [] }
                }
            }
            for await result in group {
                all.append(contentsOf: result)
            }
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
