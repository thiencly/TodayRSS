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
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        try Task.checkCancellation()
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedError.requestFailed
        }
        if let xml = String(data: data, encoding: .utf8), xml.contains("<feed") { // Atom heuristic
            return try await parseAtom(data)
        } else {
            return try await parseRSS(data)
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

