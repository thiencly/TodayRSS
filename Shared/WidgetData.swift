//
//  WidgetData.swift
//  Shared data models for widget and main app
//

import Foundation

// MARK: - App Group Identifier
let appGroupIdentifier = "group.IDKN.VibeRSS"

// MARK: - Widget Article (Codable version for widget)
struct WidgetArticle: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let link: String
    let summary: String
    let pubDate: Date?
    let thumbnailURL: String?
    let sourceTitle: String?
    let sourceIconURL: String?

    var linkURL: URL? { URL(string: link) }
    var thumbnailImageURL: URL? { thumbnailURL.flatMap { URL(string: $0) } }
    var sourceIconImageURL: URL? { sourceIconURL.flatMap { URL(string: $0) } }
}

// MARK: - Widget Feed (Codable version for widget)
struct WidgetFeed: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
    let iconURL: String?
    let folderID: String?

    var feedURL: URL? { URL(string: url) }
    var iconImageURL: URL? { iconURL.flatMap { URL(string: $0) } }
}

// MARK: - Widget Folder (Codable version for widget)
struct WidgetFolder: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

// MARK: - Widget Configuration (which source is selected)
struct WidgetSourceConfig: Codable {
    let feeds: [WidgetFeed]
    let folders: [WidgetFolder]
    let lastUpdated: Date

    static let empty = WidgetSourceConfig(feeds: [], folders: [], lastUpdated: Date.distantPast)
}

// MARK: - Widget Data Manager
class WidgetDataManager {
    static let shared = WidgetDataManager()

    private let userDefaults: UserDefaults?
    private let configKey = "widgetSourceConfig"
    private let articlesKey = "widgetArticles"

    init() {
        userDefaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    // MARK: - Source Config (feeds & folders list)

    func saveSourceConfig(_ config: WidgetSourceConfig) {
        guard let userDefaults else { return }
        do {
            let encoded = try JSONEncoder().encode(config)
            userDefaults.set(encoded, forKey: configKey)
        } catch {
            print("Failed to save widget config: \(error)")
        }
    }

    func loadSourceConfig() -> WidgetSourceConfig {
        guard let userDefaults,
              let data = userDefaults.data(forKey: configKey) else {
            return .empty
        }
        do {
            return try JSONDecoder().decode(WidgetSourceConfig.self, from: data)
        } catch {
            print("Failed to load widget config: \(error)")
            return .empty
        }
    }

    // MARK: - Cached Articles

    func saveArticles(_ articles: [String: [WidgetArticle]]) {
        guard let userDefaults else { return }
        do {
            let encoded = try JSONEncoder().encode(articles)
            userDefaults.set(encoded, forKey: articlesKey)
        } catch {
            print("Failed to save widget articles: \(error)")
        }
    }

    func loadArticles() -> [String: [WidgetArticle]] {
        guard let userDefaults,
              let data = userDefaults.data(forKey: articlesKey) else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: [WidgetArticle]].self, from: data)
        } catch {
            print("Failed to load widget articles: \(error)")
            return [:]
        }
    }

    // Get articles for a specific feed
    func articles(for feedID: String) -> [WidgetArticle] {
        let articles = loadArticles()
        return articles[feedID] ?? []
    }

    // Get articles for a folder (all feeds in that folder)
    func articles(forFolder folderID: String) -> [WidgetArticle] {
        let config = loadSourceConfig()
        let articles = loadArticles()
        let feedsInFolder = config.feeds.filter { $0.folderID == folderID }
        var allArticles: [WidgetArticle] = []
        for feed in feedsInFolder {
            if let feedArticles = articles[feed.id] {
                allArticles.append(contentsOf: feedArticles)
            }
        }
        return allArticles.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }

    // Get all articles
    func allArticles() -> [WidgetArticle] {
        let articles = loadArticles()
        var allArticles: [WidgetArticle] = []
        for feedArticles in articles.values {
            allArticles.append(contentsOf: feedArticles)
        }
        return allArticles.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }

    // Get feed by ID
    func feed(for id: String) -> WidgetFeed? {
        loadSourceConfig().feeds.first { $0.id == id }
    }

    // Get folder by ID
    func folder(for id: String) -> WidgetFolder? {
        loadSourceConfig().folders.first { $0.id == id }
    }
}
