//
//  ArticleTextCache.swift
//  VibeRSS_Test
//
//  File-based cache for extracted article text to speed up summarization.
//  Uses the app's Caches directory for automatic cleanup by the system.
//

import Foundation
import CryptoKit

actor ArticleTextCache {
    static let shared = ArticleTextCache()

    /// Call this synchronously at app launch to migrate old UserDefaults cache before any writes occur
    static func migrateFromUserDefaultsIfNeeded() {
        let storeKey = "viberss.articleTextCache"
        if UserDefaults.standard.data(forKey: storeKey) != nil {
            UserDefaults.standard.removeObject(forKey: storeKey)
            print("ArticleTextCache: Migrated from UserDefaults (cleared old cache)")
        }
    }

    private let fileManager = FileManager.default
    private let cacheDirectoryName = "ArticleTextCache"
    private let metadataFileName = "metadata.json"
    private let maxEntries = 300 // Can store more with file-based storage
    private var metadataCache: [String: CacheEntry]? = nil

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

    func cachedText(for url: URL) -> String? {
        guard let cacheDir = cacheDirectory else { return nil }

        let key = cacheKey(for: url)
        let fileURL = cacheDir.appendingPathComponent("\(key).txt")

        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        return text
    }

    func storeText(_ text: String, for url: URL) {
        guard let cacheDir = cacheDirectory,
              !text.isEmpty else { return }

        let key = cacheKey(for: url)
        let fileURL = cacheDir.appendingPathComponent("\(key).txt")

        // Write text file
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("ArticleTextCache: Failed to write: \(error)")
            return
        }

        // Update metadata
        var metadata = loadMetadata()
        metadata[key] = CacheEntry(timestamp: Date())

        // Prune if over limit
        if metadata.count > maxEntries {
            pruneCache(metadata: &metadata, cacheDir: cacheDir)
        }

        saveMetadata(metadata)
    }

    func clear() {
        guard let cacheDir = cacheDirectory else { return }

        try? fileManager.removeItem(at: cacheDir)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        metadataCache = nil

        // Also clear old UserDefaults cache if it exists
        UserDefaults.standard.removeObject(forKey: "viberss.articleTextCache")
    }

    // MARK: - Private Types

    private struct CacheEntry: Codable {
        let timestamp: Date
    }

    // MARK: - Metadata Management

    private func loadMetadata() -> [String: CacheEntry] {
        // Return cached metadata if available
        if let cached = metadataCache {
            return cached
        }

        guard let metadataURL = metadataURL,
              let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else {
            return [:]
        }

        metadataCache = metadata
        return metadata
    }

    private func saveMetadata(_ metadata: [String: CacheEntry]) {
        metadataCache = metadata

        guard let metadataURL = metadataURL else { return }

        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL)
        } catch {
            print("ArticleTextCache: Failed to save metadata: \(error)")
        }
    }

    // MARK: - Cache Pruning

    private func pruneCache(metadata: inout [String: CacheEntry], cacheDir: URL) {
        // Sort by timestamp (oldest first)
        let sorted = metadata.sorted { $0.value.timestamp < $1.value.timestamp }
        let toRemove = metadata.count - maxEntries

        for (key, _) in sorted.prefix(toRemove) {
            let fileURL = cacheDir.appendingPathComponent("\(key).txt")
            try? fileManager.removeItem(at: fileURL)
            metadata.removeValue(forKey: key)
        }

        print("ArticleTextCache: Pruned \(toRemove) entries")
    }

    // MARK: - Helper Methods

    private func cacheKey(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).compactMap { String(format: "%02x", $0) }.joined()
    }
}
