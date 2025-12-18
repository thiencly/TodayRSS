import Foundation
import SwiftUI

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

    private init() {
        loadSavedArticles()
    }

    // MARK: - Public Methods

    func isSaved(url: URL) -> Bool {
        savedArticles.contains { $0.url == url }
    }

    func save(article: SavedArticle) {
        guard !isSaved(url: article.url) else { return }
        savedArticles.insert(article, at: 0)
        persistSavedArticles()
    }

    func save(from article: Article) {
        let savedArticle = SavedArticle(from: article)
        save(article: savedArticle)
    }

    func save(url: URL, title: String, pubDate: Date?, thumbnailURL: URL?, sourceIconURL: URL?, sourceTitle: String?) {
        let savedArticle = SavedArticle(
            url: url,
            title: title,
            pubDate: pubDate,
            thumbnailURL: thumbnailURL,
            sourceIconURL: sourceIconURL,
            sourceTitle: sourceTitle
        )
        save(article: savedArticle)
    }

    func unsave(url: URL) {
        savedArticles.removeAll { $0.url == url }
        persistSavedArticles()
    }

    func toggleSaved(article: Article) {
        if isSaved(url: article.link) {
            unsave(url: article.link)
        } else {
            save(from: article)
        }
    }

    func toggleSaved(url: URL, title: String, pubDate: Date?, thumbnailURL: URL?, sourceIconURL: URL?, sourceTitle: String?) {
        if isSaved(url: url) {
            unsave(url: url)
        } else {
            save(url: url, title: title, pubDate: pubDate, thumbnailURL: thumbnailURL, sourceIconURL: sourceIconURL, sourceTitle: sourceTitle)
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
        do {
            let data = try JSONEncoder().encode(savedArticles)
            userDefaults.set(data, forKey: saveKey)
        } catch {
            print("Failed to save articles: \(error)")
        }
    }
}
