//
//  ArticleContentCache.swift
//  VibeRSS_Test
//
//  File-based cache for extracted article content to enable offline reading.
//  Stores the styled HTML and metadata from Reeeed extraction.
//

import Foundation
import CryptoKit

/// Cached article content for offline reading
struct CachedArticleContent: Codable {
    let styledHTML: String
    let baseURL: URL?
    let title: String?
    let timestamp: Date

    /// Size in bytes (approximate)
    var estimatedSize: Int {
        styledHTML.utf8.count + (title?.utf8.count ?? 0) + 100
    }
}

actor ArticleContentCache {
    static let shared = ArticleContentCache()

    private let fileManager = FileManager.default
    private let cacheDirectoryName = "ArticleContentCache"
    private let metadataFileName = "metadata.json"
    private let maxEntries = 100 // Keep last 100 articles (HTML can be large)
    private let maxCacheSizeBytes = 50 * 1024 * 1024 // 50MB max cache size
    private var metadataCache: [String: CacheMetadata]? = nil

    private var cacheDirectory: URL? {
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return cachesDir.appendingPathComponent(cacheDirectoryName, isDirectory: true)
    }

    private var metadataURL: URL? {
        cacheDirectory?.appendingPathComponent(metadataFileName)
    }

    init() {
        // Create cache directory if needed
        if let cacheDir = cacheDirectory {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Public API

    /// Check if an article is cached (fast check without loading content)
    func isCached(url: URL) -> Bool {
        guard let cacheDir = cacheDirectory else { return false }
        let key = cacheKey(for: url)
        let fileURL = cacheDir.appendingPathComponent("\(key).json")
        return fileManager.fileExists(atPath: fileURL.path)
    }

    /// Get cached article content
    func cachedContent(for url: URL) -> CachedArticleContent? {
        guard let cacheDir = cacheDirectory else { return nil }

        let key = cacheKey(for: url)
        let fileURL = cacheDir.appendingPathComponent("\(key).json")

        guard let data = try? Data(contentsOf: fileURL),
              let content = try? JSONDecoder().decode(CachedArticleContent.self, from: data) else {
            return nil
        }

        return content
    }

    /// Store article content
    func storeContent(_ content: CachedArticleContent, for url: URL) {
        guard let cacheDir = cacheDirectory,
              !content.styledHTML.isEmpty else { return }

        let key = cacheKey(for: url)
        let fileURL = cacheDir.appendingPathComponent("\(key).json")

        // Write content file
        do {
            let data = try JSONEncoder().encode(content)
            try data.write(to: fileURL)
        } catch {
            print("ArticleContentCache: Failed to write: \(error)")
            return
        }

        // Update metadata
        var metadata = loadMetadata()
        metadata[key] = CacheMetadata(
            timestamp: content.timestamp,
            size: content.estimatedSize
        )

        // Prune if over limit
        pruneIfNeeded(metadata: &metadata, cacheDir: cacheDir)

        saveMetadata(metadata)
    }

    /// Clear all cached content
    func clear() {
        guard let cacheDir = cacheDirectory else { return }

        try? fileManager.removeItem(at: cacheDir)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        metadataCache = nil
    }

    /// Get cache statistics
    func statistics() -> (count: Int, sizeBytes: Int) {
        let metadata = loadMetadata()
        let totalSize = metadata.values.reduce(0) { $0 + $1.size }
        return (metadata.count, totalSize)
    }

    // MARK: - Private Types

    private struct CacheMetadata: Codable {
        let timestamp: Date
        let size: Int
    }

    // MARK: - Metadata Management

    private func loadMetadata() -> [String: CacheMetadata] {
        if let cached = metadataCache {
            return cached
        }

        guard let metadataURL = metadataURL,
              let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode([String: CacheMetadata].self, from: data) else {
            return [:]
        }

        metadataCache = metadata
        return metadata
    }

    private func saveMetadata(_ metadata: [String: CacheMetadata]) {
        metadataCache = metadata

        guard let metadataURL = metadataURL else { return }

        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL)
        } catch {
            print("ArticleContentCache: Failed to save metadata: \(error)")
        }
    }

    // MARK: - Cache Pruning

    private func pruneIfNeeded(metadata: inout [String: CacheMetadata], cacheDir: URL) {
        // Check entry count
        let overEntryLimit = metadata.count > maxEntries

        // Check total size
        let totalSize = metadata.values.reduce(0) { $0 + $1.size }
        let overSizeLimit = totalSize > maxCacheSizeBytes

        guard overEntryLimit || overSizeLimit else { return }

        // Sort by timestamp (oldest first)
        let sorted = metadata.sorted { $0.value.timestamp < $1.value.timestamp }

        var currentSize = totalSize
        var currentCount = metadata.count
        var removed = 0

        for (key, entry) in sorted {
            // Stop if we're under both limits
            if currentCount <= maxEntries && currentSize <= maxCacheSizeBytes {
                break
            }

            let fileURL = cacheDir.appendingPathComponent("\(key).json")
            try? fileManager.removeItem(at: fileURL)
            metadata.removeValue(forKey: key)

            currentSize -= entry.size
            currentCount -= 1
            removed += 1
        }

        if removed > 0 {
            print("ArticleContentCache: Pruned \(removed) entries")
        }
    }

    // MARK: - Helper Methods

    private func cacheKey(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).compactMap { String(format: "%02x", $0) }.joined()
    }
}
