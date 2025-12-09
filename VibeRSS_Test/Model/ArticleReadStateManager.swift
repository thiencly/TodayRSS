//
//  ArticleReadStateManager.swift
//  VibeRSS_Test
//
//  Manages persistent read/seen state for articles.
//  - "Seen" = article has appeared in feed while user had app open (not new anymore)
//  - "Read" = user has tapped/opened the article
//

import Foundation

actor ArticleReadStateManager {
    static let shared = ArticleReadStateManager()

    private let seenKey = "viberss.seenArticleURLs"
    private let readKey = "viberss.readArticleURLs"
    private let latestArticlesKey = "viberss.latestArticlesBySource"
    private let maxStoredURLs = 5000 // Prevent unbounded growth

    private var seenURLs: Set<String> = []
    private var readURLs: Set<String> = []
    // Tracks the latest article URLs for each source (sourceID -> [articleURL])
    private var latestArticlesBySource: [String: [String]] = [:]

    private init() {
        loadFromDefaults()
    }

    // MARK: - Seen State (for blue dot "new" indicator)

    /// Check if an article has been seen (appeared in feed while user had app open)
    func isSeen(_ url: URL) -> Bool {
        seenURLs.contains(url.absoluteString)
    }

    /// Check if an article is new (not yet seen)
    func isNew(_ url: URL) -> Bool {
        !seenURLs.contains(url.absoluteString)
    }

    /// Mark an article as seen (removes blue dot)
    func markAsSeen(_ url: URL) {
        seenURLs.insert(url.absoluteString)
        saveSeenDebounced()
    }

    /// Mark multiple articles as seen at once
    func markAsSeen(_ urls: [URL]) {
        for url in urls {
            seenURLs.insert(url.absoluteString)
        }
        saveSeenDebounced()
    }

    // MARK: - Read State (for dimmed titles)

    /// Check if an article has been read (opened/tapped)
    func isRead(_ url: URL) -> Bool {
        readURLs.contains(url.absoluteString)
    }

    /// Mark an article as read (dims the title)
    func markAsRead(_ url: URL) {
        readURLs.insert(url.absoluteString)
        // Also mark as seen when read
        seenURLs.insert(url.absoluteString)
        saveReadDebounced()
        saveSeenDebounced()
    }

    /// Mark an article as unread
    func markAsUnread(_ url: URL) {
        readURLs.remove(url.absoluteString)
        saveReadDebounced()
    }

    // MARK: - Bulk Operations

    /// Mark all currently visible articles as seen (call when user views a feed)
    /// Uses immediate save so sidebar blue dots update correctly on return
    func markAllAsSeen(_ urls: [URL]) {
        for url in urls {
            seenURLs.insert(url.absoluteString)
        }
        saveSeenImmediate()
    }

    /// Get seen/read state for multiple URLs at once (for efficient batch queries)
    func getStates(for urls: [URL]) -> [(url: URL, isNew: Bool, isRead: Bool)] {
        urls.map { url in
            let urlString = url.absoluteString
            return (url, !seenURLs.contains(urlString), readURLs.contains(urlString))
        }
    }

    // MARK: - Source/Folder New Article Tracking

    /// Update the latest articles for a source (call when fetching feed)
    func updateLatestArticles(for sourceID: UUID, urls: [URL]) {
        let urlStrings = urls.prefix(20).map { $0.absoluteString }
        latestArticlesBySource[sourceID.uuidString] = Array(urlStrings)
        saveLatestArticlesDebounced()
    }

    /// Update latest articles with immediate save (for sidebar refresh on app launch)
    func updateLatestArticlesImmediate(for sourceID: UUID, urls: [URL]) {
        let urlStrings = urls.prefix(20).map { $0.absoluteString }
        latestArticlesBySource[sourceID.uuidString] = Array(urlStrings)
        saveLatestArticlesImmediate()
    }

    /// Check if a source has any new (unseen) articles
    func sourceHasNewArticles(_ sourceID: UUID) -> Bool {
        guard let urls = latestArticlesBySource[sourceID.uuidString] else { return false }
        return urls.contains { !seenURLs.contains($0) }
    }

    /// Check if a folder has any new articles (any of its sources have new articles)
    func folderHasNewArticles(_ folderID: UUID, sourceIDs: [UUID]) -> Bool {
        for sourceID in sourceIDs {
            if sourceHasNewArticles(sourceID) {
                return true
            }
        }
        return false
    }

    /// Get count of new articles for a source
    func newArticleCount(for sourceID: UUID) -> Int {
        guard let urls = latestArticlesBySource[sourceID.uuidString] else { return 0 }
        return urls.filter { !seenURLs.contains($0) }.count
    }

    // MARK: - Cleanup

    /// Remove old entries to prevent unbounded growth
    func cleanup() {
        // Keep only the most recent entries if over limit
        if seenURLs.count > maxStoredURLs {
            // Since Set doesn't maintain order, we just remove random entries
            // A more sophisticated approach would store timestamps
            let toRemove = seenURLs.count - maxStoredURLs
            for _ in 0..<toRemove {
                if let first = seenURLs.first {
                    seenURLs.remove(first)
                }
            }
        }
        if readURLs.count > maxStoredURLs {
            let toRemove = readURLs.count - maxStoredURLs
            for _ in 0..<toRemove {
                if let first = readURLs.first {
                    readURLs.remove(first)
                }
            }
        }
        saveSeenDebounced()
        saveReadDebounced()
    }

    /// Clear all state (for debugging/reset)
    func clearAll() {
        seenURLs.removeAll()
        readURLs.removeAll()
        latestArticlesBySource.removeAll()
        UserDefaults.standard.removeObject(forKey: seenKey)
        UserDefaults.standard.removeObject(forKey: readKey)
        UserDefaults.standard.removeObject(forKey: latestArticlesKey)
    }

    // MARK: - Persistence

    private func loadFromDefaults() {
        if let data = UserDefaults.standard.data(forKey: seenKey),
           let urls = try? JSONDecoder().decode(Set<String>.self, from: data) {
            seenURLs = urls
        }
        if let data = UserDefaults.standard.data(forKey: readKey),
           let urls = try? JSONDecoder().decode(Set<String>.self, from: data) {
            readURLs = urls
        }
        if let data = UserDefaults.standard.data(forKey: latestArticlesKey),
           let articles = try? JSONDecoder().decode([String: [String]].self, from: data) {
            latestArticlesBySource = articles
        }
    }

    private var saveSeenTask: Task<Void, Never>?
    private var saveReadTask: Task<Void, Never>?
    private var saveLatestArticlesTask: Task<Void, Never>?

    private func saveSeenDebounced() {
        saveSeenTask?.cancel()
        saveSeenTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(seenURLs) {
                UserDefaults.standard.set(data, forKey: seenKey)
            }
        }
    }

    /// Save seen URLs immediately (no debounce) - used when exiting article lists
    private func saveSeenImmediate() {
        saveSeenTask?.cancel() // Cancel any pending debounced save
        if let data = try? JSONEncoder().encode(seenURLs) {
            UserDefaults.standard.set(data, forKey: seenKey)
        }
    }

    private func saveReadDebounced() {
        saveReadTask?.cancel()
        saveReadTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(readURLs) {
                UserDefaults.standard.set(data, forKey: readKey)
            }
        }
    }

    private func saveLatestArticlesDebounced() {
        saveLatestArticlesTask?.cancel()
        saveLatestArticlesTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(latestArticlesBySource) {
                UserDefaults.standard.set(data, forKey: latestArticlesKey)
            }
        }
    }

    /// Save latest articles immediately (no debounce) - used for sidebar refresh on app launch
    private func saveLatestArticlesImmediate() {
        saveLatestArticlesTask?.cancel()
        if let data = try? JSONEncoder().encode(latestArticlesBySource) {
            UserDefaults.standard.set(data, forKey: latestArticlesKey)
        }
    }
}

// MARK: - Synchronous Access for SwiftUI

extension ArticleReadStateManager {
    /// Synchronous check using nonisolated access with cached data
    /// Note: This reads from UserDefaults directly for immediate access
    nonisolated static func isNewSync(_ url: URL) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: "viberss.seenArticleURLs"),
              let urls = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return true // If no data, article is new
        }
        return !urls.contains(url.absoluteString)
    }

    nonisolated static func isReadSync(_ url: URL) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: "viberss.readArticleURLs"),
              let urls = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return false
        }
        return urls.contains(url.absoluteString)
    }

    /// Synchronous check if a source has new articles (for sidebar)
    nonisolated static func sourceHasNewArticlesSync(_ sourceID: UUID) -> Bool {
        guard let latestData = UserDefaults.standard.data(forKey: "viberss.latestArticlesBySource"),
              let latestArticles = try? JSONDecoder().decode([String: [String]].self, from: latestData),
              let articleURLs = latestArticles[sourceID.uuidString] else {
            return false
        }

        guard let seenData = UserDefaults.standard.data(forKey: "viberss.seenArticleURLs"),
              let seenURLs = try? JSONDecoder().decode(Set<String>.self, from: seenData) else {
            // No seen data means all articles are new
            return !articleURLs.isEmpty
        }

        return articleURLs.contains { !seenURLs.contains($0) }
    }

    /// Synchronous check if a folder has new articles (for sidebar)
    nonisolated static func folderHasNewArticlesSync(_ folderID: UUID, sourceIDs: [UUID]) -> Bool {
        for sourceID in sourceIDs {
            if sourceHasNewArticlesSync(sourceID) {
                return true
            }
        }
        return false
    }
}
