//
//  NewsReelViewModel.swift
//  VibeRSS_Test
//
//  ViewModel for TikTok-style news reel feature
//

import SwiftUI
import Combine

/// Represents a source option in the news reel (All, or a specific folder)
enum ReelSource: Hashable, Identifiable {
    case all
    case folder(Folder)

    var id: String {
        switch self {
        case .all: return "all"
        case .folder(let folder): return folder.id.uuidString
        }
    }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .folder(let folder): return folder.name
        }
    }
}

@MainActor
final class NewsReelViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var currentArticleIndex: Int = 0
    @Published var currentSourceIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    /// All available sources (All + folders)
    @Published var sources: [ReelSource] = []

    /// Articles for each source, keyed by source ID
    @Published private(set) var articlesBySource: [String: [Article]] = [:]

    /// Reel summaries cache, keyed by article URL
    @Published private(set) var reelSummaries: [URL: String] = [:]

    /// Expanded (short) summaries cache, keyed by article URL
    @Published private(set) var expandedSummaries: [URL: String] = [:]

    /// Loading state for summaries
    @Published private(set) var loadingSummaryURLs: Set<URL> = []

    // MARK: - Private Properties

    private let feedService = FeedService()
    private var feeds: [Feed] = []
    private var prefetchTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var currentSource: ReelSource? {
        guard currentSourceIndex >= 0 && currentSourceIndex < sources.count else { return nil }
        return sources[currentSourceIndex]
    }

    var currentArticles: [Article] {
        guard let source = currentSource else { return [] }
        return articlesBySource[source.id] ?? []
    }

    var currentArticle: Article? {
        guard currentArticleIndex >= 0 && currentArticleIndex < currentArticles.count else { return nil }
        return currentArticles[currentArticleIndex]
    }

    var hasNextArticle: Bool {
        currentArticleIndex < currentArticles.count - 1
    }

    var hasPreviousArticle: Bool {
        currentArticleIndex > 0
    }

    var hasNextSource: Bool {
        currentSourceIndex < sources.count - 1
    }

    var hasPreviousSource: Bool {
        currentSourceIndex > 0
    }

    // MARK: - Initialization

    func initialize(folders: [Folder], feeds: [Feed]) {
        self.feeds = feeds

        // Build sources list: All + each folder
        var sourcesList: [ReelSource] = [.all]
        sourcesList.append(contentsOf: folders.map { .folder($0) })
        self.sources = sourcesList

        // Load articles for initial source
        Task {
            await loadArticlesForCurrentSource()
        }
    }

    // MARK: - Navigation

    func nextArticle() {
        guard hasNextArticle else { return }
        currentArticleIndex += 1
        prefetchAdjacentSummaries()
    }

    func previousArticle() {
        guard hasPreviousArticle else { return }
        currentArticleIndex -= 1
        prefetchAdjacentSummaries()
    }

    func nextSource() {
        guard hasNextSource else { return }
        currentSourceIndex += 1
        currentArticleIndex = 0

        Task {
            await loadArticlesForCurrentSource()
        }
    }

    func previousSource() {
        guard hasPreviousSource else { return }
        currentSourceIndex -= 1
        currentArticleIndex = 0

        Task {
            await loadArticlesForCurrentSource()
        }
    }

    func selectSource(at index: Int) {
        guard index >= 0 && index < sources.count else { return }
        guard index != currentSourceIndex else { return }

        currentSourceIndex = index
        currentArticleIndex = 0

        Task {
            await loadArticlesForCurrentSource()
        }
    }

    // MARK: - Article Loading

    private func loadArticlesForCurrentSource() async {
        guard let source = currentSource else { return }

        // Check if already loaded
        if let existing = articlesBySource[source.id], !existing.isEmpty {
            prefetchAdjacentSummaries()
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let articles = try await loadArticles(for: source)
            articlesBySource[source.id] = articles
            prefetchAdjacentSummaries()
        } catch {
            errorMessage = "Failed to load articles"
        }

        isLoading = false
    }

    private func loadArticles(for source: ReelSource) async throws -> [Article] {
        var allArticles: [Article] = []

        let feedsToLoad: [Feed]
        switch source {
        case .all:
            feedsToLoad = feeds
        case .folder(let folder):
            feedsToLoad = feeds.filter { $0.folderID == folder.id }
        }

        // Capture feedService before entering task group to avoid actor isolation issues
        let service = self.feedService

        // Load all feeds concurrently using TaskGroup
        await withTaskGroup(of: [FeedItem].self) { group in
            for feed in feedsToLoad {
                group.addTask {
                    do {
                        var items = try await service.loadItems(from: feed.url)
                        // Add source attribution
                        for i in items.indices {
                            items[i].sourceID = feed.id
                            items[i].sourceTitle = feed.title
                            items[i].sourceIconURL = feed.iconURL
                        }
                        return items
                    } catch {
                        return []
                    }
                }
            }

            for await items in group {
                allArticles.append(contentsOf: items)
            }
        }

        // Sort by date (newest first)
        let sorted = allArticles.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }

        return sorted
    }

    // MARK: - Summary Management

    /// Get reel summary for an article, generating if needed
    func reelSummary(for article: Article) -> String? {
        return reelSummaries[article.link]
    }

    /// Get expanded (short) summary for an article
    func expandedSummary(for article: Article) -> String? {
        return expandedSummaries[article.link]
    }

    /// Check if summary is currently loading
    func isSummaryLoading(for article: Article) -> Bool {
        return loadingSummaryURLs.contains(article.link)
    }

    /// Generate reel summary for article
    func generateReelSummary(for article: Article) async {
        let url = article.link

        // Check if already cached
        if reelSummaries[url] != nil { return }

        // Check if already loading
        guard !loadingSummaryURLs.contains(url) else { return }

        loadingSummaryURLs.insert(url)

        let summary = await ArticleSummarizer.shared.fastReelSummary(
            url: url,
            articleText: article.summary.isEmpty ? nil : article.summary
        )

        if let summary = summary {
            reelSummaries[url] = summary
        }

        loadingSummaryURLs.remove(url)
    }

    /// Cache an expanded summary for an article
    func cacheExpandedSummary(_ summary: String, for article: Article) {
        expandedSummaries[article.link] = summary
    }

    /// Clear cached expanded summary for an article (used when length changes)
    func clearExpandedSummary(for article: Article) {
        expandedSummaries[article.link] = nil
    }

    // MARK: - Prefetching

    /// Prefetch summaries for articles adjacent to current one
    private func prefetchAdjacentSummaries() {
        prefetchTask?.cancel()

        prefetchTask = Task {
            let articles = currentArticles
            let currentIdx = currentArticleIndex

            // Prefetch for current and ±2 articles
            let indicesToPrefetch = [currentIdx, currentIdx - 1, currentIdx - 2, currentIdx + 1, currentIdx + 2]
                .filter { $0 >= 0 && $0 < articles.count }

            for idx in indicesToPrefetch {
                guard !Task.isCancelled else { return }
                let article = articles[idx]

                // Only generate if not already cached
                if reelSummaries[article.link] == nil {
                    await generateReelSummary(for: article)
                }
            }
        }
    }

    /// Force refresh articles for current source
    func refresh() async {
        guard let source = currentSource else { return }

        // Clear cached articles for this source
        articlesBySource[source.id] = nil
        currentArticleIndex = 0

        await loadArticlesForCurrentSource()
    }
}
