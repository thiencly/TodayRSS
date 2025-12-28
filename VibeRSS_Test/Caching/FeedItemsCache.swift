//
//  FeedItemsCache.swift
//  VibeRSS_Test
//
//  File-based cache for feed item lists to enable instant feed loading.
//  Stores the article list (titles, links, dates, summaries) per feed.
//  When user opens a feed, cached items are shown immediately.
//

import Foundation

/// Cached feed item for persistence
struct CachedFeedItem: Codable {
    let title: String
    let link: URL
    let summary: String
    let pubDate: Date?
    let author: String?
    let thumbnailURL: URL?
}

/// Metadata for a cached feed
struct CachedFeedMetadata: Codable {
    let feedID: UUID
    let feedTitle: String
    let feedIconURL: URL?
    let lastUpdated: Date
    let items: [CachedFeedItem]
}

actor FeedItemsCache {
    static let shared = FeedItemsCache()

    private let fileManager = FileManager.default
    private let cacheDirectoryName = "FeedItemsCache"
    private var memoryCache: [UUID: CachedFeedMetadata] = [:]

    private var cacheDirectory: URL? {
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return cachesDir.appendingPathComponent(cacheDirectoryName, isDirectory: true)
    }

    init() {
        // Create cache directory if needed
        if let cacheDir = cacheDirectory {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Public API

    /// Store feed items for a feed
    func storeFeedItems(_ items: [FeedItem], for feedID: UUID, feedTitle: String, feedIconURL: URL?) {
        guard let cacheDir = cacheDirectory else { return }

        let cachedItems = items.map { item in
            CachedFeedItem(
                title: item.title,
                link: item.link,
                summary: item.summary,
                pubDate: item.pubDate,
                author: item.author,
                thumbnailURL: item.thumbnailURL
            )
        }

        let metadata = CachedFeedMetadata(
            feedID: feedID,
            feedTitle: feedTitle,
            feedIconURL: feedIconURL,
            lastUpdated: Date(),
            items: cachedItems
        )

        // Update memory cache
        memoryCache[feedID] = metadata

        // Write to disk
        let fileURL = cacheDir.appendingPathComponent("\(feedID.uuidString).json")
        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: fileURL, options: .atomicWrite)
        } catch {
            print("FeedItemsCache: Failed to write feed \(feedID): \(error)")
        }
    }

    /// Get cached feed items for a feed
    func getCachedItems(for feedID: UUID) -> CachedFeedMetadata? {
        // Check memory cache first
        if let cached = memoryCache[feedID] {
            return cached
        }

        // Load from disk
        guard let cacheDir = cacheDirectory else { return nil }
        let fileURL = cacheDir.appendingPathComponent("\(feedID.uuidString).json")

        guard let data = try? Data(contentsOf: fileURL),
              let metadata = try? JSONDecoder().decode(CachedFeedMetadata.self, from: data) else {
            return nil
        }

        // Update memory cache
        memoryCache[feedID] = metadata
        return metadata
    }

    /// Check if a feed has cached items
    func hasCachedItems(for feedID: UUID) -> Bool {
        if memoryCache[feedID] != nil {
            return true
        }

        guard let cacheDir = cacheDirectory else { return false }
        let fileURL = cacheDir.appendingPathComponent("\(feedID.uuidString).json")
        return fileManager.fileExists(atPath: fileURL.path)
    }

    /// Get the last updated timestamp for a feed
    func getLastUpdated(for feedID: UUID) -> Date? {
        return getCachedItems(for: feedID)?.lastUpdated
    }

    /// Convert cached items back to FeedItem array
    func getFeedItems(for feedID: UUID, sourceID: UUID, sourceTitle: String, sourceIconURL: URL?) -> [FeedItem]? {
        guard let cached = getCachedItems(for: feedID) else { return nil }

        return cached.items.map { item in
            var feedItem = FeedItem(
                title: item.title,
                link: item.link,
                summary: item.summary,
                pubDate: item.pubDate,
                author: item.author,
                thumbnailURL: item.thumbnailURL
            )
            feedItem.sourceID = sourceID
            feedItem.sourceTitle = sourceTitle
            feedItem.sourceIconURL = sourceIconURL
            return feedItem
        }
    }

    /// Clear cache for a specific feed
    func clearCache(for feedID: UUID) {
        memoryCache.removeValue(forKey: feedID)

        guard let cacheDir = cacheDirectory else { return }
        let fileURL = cacheDir.appendingPathComponent("\(feedID.uuidString).json")
        try? fileManager.removeItem(at: fileURL)
    }

    /// Clear all cached feeds
    func clearAll() {
        memoryCache.removeAll()

        guard let cacheDir = cacheDirectory else { return }
        try? fileManager.removeItem(at: cacheDir)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Get cache statistics
    func statistics() -> (feedCount: Int, totalItems: Int) {
        guard let cacheDir = cacheDirectory else { return (0, 0) }

        var feedCount = 0
        var totalItems = 0

        guard let files = try? fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else {
            return (0, 0)
        }

        for file in files where file.pathExtension == "json" {
            feedCount += 1
            if let data = try? Data(contentsOf: file),
               let metadata = try? JSONDecoder().decode(CachedFeedMetadata.self, from: data) {
                totalItems += metadata.items.count
            }
        }

        return (feedCount, totalItems)
    }

    /// Preload all cached feeds into memory for faster access
    func preloadCache() {
        guard let cacheDir = cacheDirectory else { return }

        guard let files = try? fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else {
            return
        }

        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let metadata = try? JSONDecoder().decode(CachedFeedMetadata.self, from: data) {
                memoryCache[metadata.feedID] = metadata
            }
        }
    }
}
