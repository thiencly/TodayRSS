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

actor FeedService {
    func loadItems(from url: URL) async throws -> [FeedItem] {
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
                print("[FeedService] Failed to load from \(effectiveURL): \(error)")
                lastError = error
                continue
            }
        }

        throw lastError
    }

    private func loadItemsFromURL(_ url: URL) async throws -> [FeedItem] {
        print("[FeedService] Loading from: \(url)")

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        try Task.checkCancellation()

        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else {
            print("[FeedService] No HTTP response")
            throw FeedError.requestFailed
        }

        print("[FeedService] Status: \(http.statusCode), Size: \(data.count) bytes")

        guard (200..<300).contains(http.statusCode) else {
            print("[FeedService] Bad status code: \(http.statusCode)")
            throw FeedError.requestFailed
        }

        if let xml = String(data: data, encoding: .utf8) {
            if xml.contains("<feed") { // Atom heuristic
                return try await parseAtom(data)
            } else if xml.contains("<rss") || xml.contains("<channel") {
                return try await parseRSS(data)
            } else {
                print("[FeedService] Unknown feed format. First 500 chars: \(String(xml.prefix(500)))")
                throw FeedError.parseFailed
            }
        } else {
            print("[FeedService] Could not decode data as UTF-8")
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

