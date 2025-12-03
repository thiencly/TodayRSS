//
//  WidgetUpdater.swift
//  Helper to update widget data from main app
//

import Foundation
import WidgetKit

@MainActor
class WidgetUpdater {
    static let shared = WidgetUpdater()

    private var debounceTask: Task<Void, Never>?

    /// Update widget source config (feeds & folders list)
    /// Call this when feeds or folders change
    func updateSourceConfig(feeds: [Feed], folders: [Folder]) {
        // Convert to widget-compatible format
        let widgetFeeds = feeds.map { feed in
            WidgetFeed(
                id: feed.id.uuidString,
                title: feed.title,
                url: feed.url.absoluteString,
                iconURL: feed.iconURL?.absoluteString,
                folderID: feed.folderID?.uuidString
            )
        }

        let widgetFolders = folders.map { folder in
            WidgetFolder(
                id: folder.id.uuidString,
                name: folder.name
            )
        }

        let config = WidgetSourceConfig(
            feeds: widgetFeeds,
            folders: widgetFolders,
            lastUpdated: Date()
        )

        // Save to App Group
        WidgetDataManager.shared.saveSourceConfig(config)

        // Reload widget timelines so they can fetch new feeds
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Update cached articles for widgets
    /// Call this after fetching articles from feeds
    func updateArticles(articlesByFeed: [UUID: [FeedItem]]) {
        // Debounce to avoid excessive updates
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }

            var widgetArticles: [String: [WidgetArticle]] = [:]
            for (feedID, articles) in articlesByFeed {
                let converted = articles.prefix(10).map { article in
                    WidgetArticle(
                        id: article.id.uuidString,
                        title: article.title,
                        link: article.link.absoluteString,
                        summary: article.summary,
                        pubDate: article.pubDate,
                        thumbnailURL: article.thumbnailURL?.absoluteString,
                        sourceTitle: article.sourceTitle,
                        sourceIconURL: article.sourceIconURL?.absoluteString
                    )
                }
                widgetArticles[feedID.uuidString] = Array(converted)
            }

            // Save to App Group
            WidgetDataManager.shared.saveArticles(widgetArticles)

            // Reload widget timelines
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Quick update just to refresh timelines
    func reloadTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
