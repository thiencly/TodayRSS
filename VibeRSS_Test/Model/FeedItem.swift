// FILE: Models/FeedItem.swift
// PURPOSE: Represents an article/post item parsed from a feed
// SAFE TO EDIT: Yes, keep fields consistent with parsing and UI

import Foundation

struct FeedItem: Identifiable, Hashable, Equatable {
    let id = UUID()
    var title: String
    var link: URL
    var summary: String
    var pubDate: Date?
    var author: String?
    var thumbnailURL: URL?

    // Source attribution (set by view models after parsing)
    var sourceID: UUID? = nil
    var sourceTitle: String? = nil
    var sourceIconURL: URL? = nil

    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.link == rhs.link &&
        lhs.summary == rhs.summary &&
        lhs.pubDate == rhs.pubDate &&
        lhs.author == rhs.author &&
        lhs.thumbnailURL == rhs.thumbnailURL &&
        lhs.sourceID == rhs.sourceID &&
        lhs.sourceTitle == rhs.sourceTitle &&
        lhs.sourceIconURL == rhs.sourceIconURL
    }
}

// Terminology alias used throughout the app
typealias Article = FeedItem