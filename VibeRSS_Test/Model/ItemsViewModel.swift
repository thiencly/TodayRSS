import SwiftUI
import Combine
import WidgetKit

@MainActor
final class ItemsViewModel: ObservableObject {
    @Published var items: [Article] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var newArticleIDs: Set<UUID> = []

    private let service = FeedService()
    private var previousArticleIDs: Set<UUID> = []

    func load(for source: Source) async {
        isLoading = true; errorMessage = nil
        do {
            var result = try await service.loadItems(from: source.url)
            for i in result.indices {
                result[i].sourceID = source.id
                result[i].sourceTitle = source.title
                result[i].sourceIconURL = source.iconURL
            }

            // Sync to widgets
            WidgetUpdater.shared.syncFeedToWidget(feedID: source.id, articles: result)

            guard let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()) else {
                // If date math fails, keep existing items order without filtering
                let sorted = result.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
                updateNewArticles(from: sorted)
                items = sorted
                isLoading = false
                return
            }
            // Updated filter logic for pubDate nil items kept
            result = result.filter { item in
                if let d = item.pubDate { return d >= cutoff } else { return true }
            }
            let sorted = result.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            updateNewArticles(from: sorted)
            items = sorted
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
