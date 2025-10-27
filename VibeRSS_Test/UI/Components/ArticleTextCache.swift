//
//  ArticleTextCache.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/27/25.
//


//
//  ArticleTextCache.swift
//  TodayRSS
//
//  Purpose:
//  - Provides a lightweight, in-memory + UserDefaults-backed cache for extracted
//    readable article text to speed up summarization and reduce network work.
//  - Used by ArticleSummarizer and prefetch logic to avoid re-fetching/parsing.
//
//  Used by:
//  - ArticleSummarizer (reads/writes cached text)
//  - ContentView global refresh prefetch (reads/writes cached text)
//

import Foundation

actor ArticleTextCache {
    static let shared = ArticleTextCache()

    private var cache: [String: String] = [:] // key: url.absoluteString
    private let storeKey = "viberss.articleTextCache"
    private var saveDebounceTask: Task<Void, Never>? = nil

    init() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = dict
        }
    }

    func cachedText(for url: URL) -> String? {
        cache[url.absoluteString]
    }

    func storeText(_ text: String, for url: URL) {
        cache[url.absoluteString] = text
        debounceSave()
    }

    func clear() {
        cache.removeAll()
        UserDefaults.standard.removeObject(forKey: storeKey)
    }

    private func debounceSave() {
        saveDebounceTask?.cancel()
        let snapshot = cache
        saveDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: storeKey)
            }
        }
    }
}