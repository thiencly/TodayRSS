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

    /// Loading state for summaries
    @Published private(set) var loadingSummaryURLs: Set<URL> = []

    /// Saved article positions for each source (to restore when switching back)
    private var savedArticlePositions: [Int: Int] = [:]

    // MARK: - Private Properties

    private let feedService = FeedService()
    private var feeds: [Feed] = []
    private var prefetchTask: Task<Void, Never>?

    /// Track failed summary attempts for retry logic
    private var failedSummaryAttempts: [URL: (count: Int, lastAttempt: Date)] = [:]
    private let maxRetryAttempts = 3
    private let retryDelaySeconds: [Double] = [2, 5, 10] // Exponential backoff

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

    /// Get articles for a specific source index (used for rendering adjacent sources during transitions)
    func articles(forSourceAt index: Int) -> [Article] {
        guard index >= 0 && index < sources.count else { return [] }
        let source = sources[index]
        return articlesBySource[source.id] ?? []
    }

    /// Get saved article position for a source
    func savedArticlePosition(forSourceAt index: Int) -> Int {
        return savedArticlePositions[index] ?? 0
    }

    /// Save article position for a source
    func saveArticlePosition(_ position: Int, forSourceAt index: Int) {
        savedArticlePositions[index] = position
    }

    /// Preload articles for adjacent sources (for smooth transitions)
    func preloadAdjacentSources() async {
        // Preload previous source
        if hasPreviousSource {
            let prevSource = sources[currentSourceIndex - 1]
            if articlesBySource[prevSource.id] == nil {
                if let articles = try? await loadArticles(for: prevSource) {
                    articlesBySource[prevSource.id] = articles
                }
            }
        }

        // Preload next source
        if hasNextSource {
            let nextSource = sources[currentSourceIndex + 1]
            if articlesBySource[nextSource.id] == nil {
                if let articles = try? await loadArticles(for: nextSource) {
                    articlesBySource[nextSource.id] = articles
                }
            }
        }
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
        // Restore saved position for this source
        currentArticleIndex = savedArticlePositions[currentSourceIndex] ?? 0

        Task {
            await loadArticlesForCurrentSource()
        }
    }

    func previousSource() {
        guard hasPreviousSource else { return }
        currentSourceIndex -= 1
        // Restore saved position for this source
        currentArticleIndex = savedArticlePositions[currentSourceIndex] ?? 0

        Task {
            await loadArticlesForCurrentSource()
        }
    }

    func selectSource(at index: Int) {
        guard index >= 0 && index < sources.count else { return }
        guard index != currentSourceIndex else { return }

        currentSourceIndex = index
        // Restore saved position for this source
        currentArticleIndex = savedArticlePositions[index] ?? 0

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

        // Filter to only show articles from today
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let todayArticles = allArticles.filter { article in
            guard let pubDate = article.pubDate else { return false }
            return pubDate >= startOfToday
        }

        // Sort by date (newest first)
        let sorted = todayArticles.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }

        return sorted
    }

    // MARK: - Summary Management

    /// Get reel summary for an article, generating if needed
    func reelSummary(for article: Article) -> String? {
        return reelSummaries[article.link]
    }

    /// Check if summary is currently loading
    func isSummaryLoading(for article: Article) -> Bool {
        return loadingSummaryURLs.contains(article.link)
    }

    /// Check if summary generation has failed (exhausted retries)
    func hasSummaryFailed(for article: Article) -> Bool {
        guard let failureInfo = failedSummaryAttempts[article.link] else { return false }
        return failureInfo.count >= maxRetryAttempts
    }

    /// Check if summary is currently retrying
    func isSummaryRetrying(for article: Article) -> Bool {
        guard let failureInfo = failedSummaryAttempts[article.link] else { return false }
        return failureInfo.count > 0 && failureInfo.count < maxRetryAttempts
    }

    /// Generate reel summary for article with automatic retry on failure
    func generateReelSummary(for article: Article) async {
        let url = article.link

        // Check if already cached
        if reelSummaries[url] != nil { return }

        // Check if already loading
        guard !loadingSummaryURLs.contains(url) else { return }

        // Check if we've exceeded max retries
        if let failureInfo = failedSummaryAttempts[url], failureInfo.count >= maxRetryAttempts {
            return
        }

        loadingSummaryURLs.insert(url)

        let summary = await ArticleSummarizer.shared.fastReelSummary(
            url: url,
            articleText: article.summary.isEmpty ? nil : article.summary
        )

        if let summary = summary {
            reelSummaries[url] = summary
            failedSummaryAttempts.removeValue(forKey: url) // Clear any failure tracking
        } else {
            // Track failure and schedule retry
            let currentCount = failedSummaryAttempts[url]?.count ?? 0
            failedSummaryAttempts[url] = (count: currentCount + 1, lastAttempt: Date())

            // Schedule automatic retry if under max attempts
            if currentCount + 1 < maxRetryAttempts {
                let delay = retryDelaySeconds[min(currentCount, retryDelaySeconds.count - 1)]
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    // Only retry if still viewing this article and not already cached
                    if reelSummaries[url] == nil && !loadingSummaryURLs.contains(url) {
                        await self.generateReelSummary(for: article)
                    }
                }
            }
        }

        loadingSummaryURLs.remove(url)
    }

    /// Force retry summary generation for an article (resets failure count)
    func retryReelSummary(for article: Article) async {
        let url = article.link
        failedSummaryAttempts.removeValue(forKey: url)
        reelSummaries.removeValue(forKey: url)
        await generateReelSummary(for: article)
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
