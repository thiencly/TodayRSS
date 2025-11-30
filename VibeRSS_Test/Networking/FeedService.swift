//// FILE: Networking/FeedService.swift
// PURPOSE: Downloads and parses RSS/Atom feed items
// SAFE TO EDIT: Yes, but keep method signatures used by view models

import Foundation

enum FeedError: Error, LocalizedError {
    case badURL, requestFailed, parseFailed

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid feed URL"
        case .requestFailed: return "Network request failed"
        case .parseFailed: return "Couldn't parse feed"
        }
    }
}

// MARK: - RSS Response Cache with Request Coalescing

private actor RSSCache {
    static let shared = RSSCache()

    private struct CachedResponse {
        let items: [FeedItem]
        let timestamp: Date
    }

    private var cache: [URL: CachedResponse] = [:]
    private var inFlightRequests: [URL: Task<[FeedItem], Error>] = [:]
    private let cacheDuration: TimeInterval = 60 // 1 minute cache

    func get(for url: URL) -> [FeedItem]? {
        guard let cached = cache[url] else { return nil }

        // Check if cache is still valid
        if Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.items
        } else {
            // Expired, remove it
            cache.removeValue(forKey: url)
            return nil
        }
    }

    func set(_ items: [FeedItem], for url: URL) {
        cache[url] = CachedResponse(items: items, timestamp: Date())
    }

    func clear() {
        cache.removeAll()
    }

    /// Check if there's an in-flight request for this URL and return it, or register a new one
    func getOrCreateInFlightRequest(for url: URL, factory: @escaping () async throws -> [FeedItem]) async throws -> [FeedItem] {
        // Check cache first
        if let cached = get(for: url) {
            return cached
        }

        // Check if there's already an in-flight request
        if let existingTask = inFlightRequests[url] {
            return try await existingTask.value
        }

        // Create new request task
        let task = Task {
            try await factory()
        }
        inFlightRequests[url] = task

        do {
            let items = try await task.value
            set(items, for: url)
            inFlightRequests.removeValue(forKey: url)
            return items
        } catch {
            inFlightRequests.removeValue(forKey: url)
            throw error
        }
    }
}

actor FeedService {
    func loadItems(from url: URL) async throws -> [FeedItem] {
        // Use cache with request coalescing to avoid duplicate simultaneous requests
        return try await RSSCache.shared.getOrCreateInFlightRequest(for: url) {
            try await self.fetchFromNetwork(url: url)
        }
    }

    private func fetchFromNetwork(url: URL) async throws -> [FeedItem] {
        // Try HTTPS first, fall back to original URL if it fails
        var urlsToTry: [URL] = []

        if url.scheme == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            if let httpsURL = components.url {
                urlsToTry.append(httpsURL)
            }
        }
        urlsToTry.append(url)

        var lastError: Error = FeedError.requestFailed

        for effectiveURL in urlsToTry {
            do {
                return try await loadItemsFromURL(effectiveURL)
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError
    }

    private func loadItemsFromURL(_ url: URL) async throws -> [FeedItem] {

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        try Task.checkCancellation()

        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else {
            throw FeedError.requestFailed
        }

        guard (200..<300).contains(http.statusCode) else {
            throw FeedError.requestFailed
        }

        if let xml = String(data: data, encoding: .utf8) {
            if xml.contains("<feed") { // Atom heuristic
                return try await parseAtom(data)
            } else if xml.contains("<rss") || xml.contains("<channel") {
                return try await parseRSS(data)
            } else {
                throw FeedError.parseFailed
            }
        } else {
            throw FeedError.parseFailed
        }
    }

    @MainActor private func parseRSS(_ data: Data) throws -> [FeedItem] {
        let parser = RSSParser()
        return try parser.parse(data: data)
    }

    @MainActor private func parseAtom(_ data: Data) throws -> [FeedItem] {
        let parser = AtomParser()
        return try parser.parse(data: data)
    }
}//  Feedservice.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/26/25.
//

