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

    func load(for source: Source) async {
        isLoading = true; errorMessage = nil
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
            let filtered = filterByAge(sorted)
            updateNewArticles(from: filtered)
            items = filtered
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
}
