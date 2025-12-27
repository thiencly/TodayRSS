import Foundation
import SwiftUI
import Reeeed

// MARK: - Saved Article Model

struct SavedArticle: Codable, Identifiable, Equatable {
    var id: UUID
    let url: URL
    let title: String
    let pubDate: Date?
    let thumbnailURL: URL?
    let sourceIconURL: URL?
    let sourceTitle: String?
    let savedDate: Date

    init(id: UUID = UUID(), url: URL, title: String, pubDate: Date?, thumbnailURL: URL?, sourceIconURL: URL?, sourceTitle: String?, savedDate: Date = Date()) {
        self.id = id
        self.url = url
        self.title = title
        self.pubDate = pubDate
        self.thumbnailURL = thumbnailURL
        self.sourceIconURL = sourceIconURL
        self.sourceTitle = sourceTitle
        self.savedDate = savedDate
    }

    // Create from Article/FeedItem
    init(from article: Article) {
        self.id = UUID()
        self.url = article.link
        self.title = article.title
        self.pubDate = article.pubDate
        self.thumbnailURL = article.thumbnailURL
        self.sourceIconURL = article.sourceIconURL
        self.sourceTitle = article.sourceTitle
        self.savedDate = Date()
    }
}

// MARK: - Saved Articles Manager

@Observable
final class SavedArticlesManager {
    static let shared = SavedArticlesManager()

    private(set) var savedArticles: [SavedArticle] = []
    private let saveKey = "savedArticles"
    private let userDefaults = UserDefaults.standard

    private var maxSavedArticles: Int {
        EntitlementManager.shared.savedArticlesLimit
    }

    private init() {
        loadSavedArticles()
        // Auto cleanup on init if over limit
        pruneIfNeeded()
    }

    // MARK: - Public Methods

    func isSaved(url: URL) -> Bool {
        savedArticles.contains { $0.url == url }
    }

    /// Returns true if saved successfully, false if limit reached
    @discardableResult
    func save(article: SavedArticle) -> Bool {
        guard !isSaved(url: article.url) else { return true }

        // Check entitlement limit
        guard EntitlementManager.shared.canSaveArticle(currentCount: savedArticles.count) else {
            return false
        }

        savedArticles.insert(article, at: 0)
        persistSavedArticles()

        // Cache article for offline reading in the background
        Task {
            await cacheArticleForOffline(article)
        }

        return true
    }

    /// Cache a saved article for offline reading
    private func cacheArticleForOffline(_ article: SavedArticle) async {
        // Skip if already cached
        if await ArticleContentCache.shared.cachedContent(for: article.url) != nil {
            return
        }

        do {
            // Fetch and cache full styled HTML using Reeeed
            let result = try await Reeeed.fetchAndExtractContent(fromURL: article.url)

            // Cache the styled HTML
            let cached = CachedArticleContent(
                styledHTML: result.styledHTML,
                baseURL: result.baseURL,
                title: result.extracted.title,
                timestamp: Date()
            )
            await ArticleContentCache.shared.storeContent(cached, for: article.url)

            // Also cache extracted text for summaries
            let text = ArticleSummarizer.shared.extractReadableText(from: result.styledHTML)
            if !text.isEmpty {
                await ArticleTextCache.shared.storeText(
                    text,
                    for: article.url,
                    title: article.title,
                    sourceTitle: article.sourceTitle,
                    pubDate: article.pubDate
                )
            }

            print("Cached saved article for offline: \(article.title)")
        } catch {
            print("Failed to cache saved article: \(error.localizedDescription)")
        }
    }

    /// Returns true if saved successfully, false if limit reached
    @discardableResult
    func save(from article: Article) -> Bool {
        let savedArticle = SavedArticle(from: article)
        return save(article: savedArticle)
    }

    /// Returns true if saved successfully, false if limit reached
    @discardableResult
    func save(url: URL, title: String, pubDate: Date?, thumbnailURL: URL?, sourceIconURL: URL?, sourceTitle: String?) -> Bool {
        let savedArticle = SavedArticle(
            url: url,
            title: title,
            pubDate: pubDate,
            thumbnailURL: thumbnailURL,
            sourceIconURL: sourceIconURL,
            sourceTitle: sourceTitle
        )
        return save(article: savedArticle)
    }

    func unsave(url: URL) {
        savedArticles.removeAll { $0.url == url }
        persistSavedArticles()
    }

    /// Returns true if operation succeeded, false if save limit reached
    @discardableResult
    func toggleSaved(article: Article) -> Bool {
        if isSaved(url: article.link) {
            unsave(url: article.link)
            return true
        } else {
            return save(from: article)
        }
    }

    /// Returns true if operation succeeded, false if save limit reached
    @discardableResult
    func toggleSaved(url: URL, title: String, pubDate: Date?, thumbnailURL: URL?, sourceIconURL: URL?, sourceTitle: String?) -> Bool {
        if isSaved(url: url) {
            unsave(url: url)
            return true
        } else {
            return save(url: url, title: title, pubDate: pubDate, thumbnailURL: thumbnailURL, sourceIconURL: sourceIconURL, sourceTitle: sourceTitle)
        }
    }

    // MARK: - Persistence

    private func loadSavedArticles() {
        guard let data = userDefaults.data(forKey: saveKey) else { return }
        do {
            savedArticles = try JSONDecoder().decode([SavedArticle].self, from: data)
        } catch {
            print("Failed to load saved articles: \(error)")
        }
    }

    private func persistSavedArticles() {
        // Enforce limit before saving
        pruneIfNeeded()
        do {
            let data = try JSONEncoder().encode(savedArticles)
            userDefaults.set(data, forKey: saveKey)
        } catch {
            print("Failed to save articles: \(error)")
        }
    }

    // MARK: - Cleanup

    /// Remove oldest saved articles if over limit
    private func pruneIfNeeded() {
        guard savedArticles.count > maxSavedArticles else { return }
        // Articles are sorted newest first (inserted at index 0)
        // So we keep the first maxSavedArticles
        savedArticles = Array(savedArticles.prefix(maxSavedArticles))
        print("✓ SavedArticlesManager: Pruned to \(maxSavedArticles) articles")
    }
}
