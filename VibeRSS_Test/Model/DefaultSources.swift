//
//  DefaultSources.swift
//  VibeRSS_Test
//
//  Default RSS sources organized by category for onboarding and quick setup.
//

import Foundation
import SwiftUI

// MARK: - Source Category

struct SourceCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let iconColor: Color
    let sources: [DefaultSource]
}

struct DefaultSource: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    let iconURL: URL?

    init(title: String, urlString: String, iconURL: String? = nil) {
        self.title = title
        self.url = URL(string: urlString)!
        self.iconURL = iconURL.flatMap { URL(string: $0) }
    }
}

// MARK: - Default Sources Data

enum DefaultSources {
    static let categories: [SourceCategory] = [
        SourceCategory(
            name: "Tech & Gadgets",
            icon: "laptopcomputer",
            iconColor: .blue,
            sources: [
                DefaultSource(
                    title: "The Verge",
                    urlString: "https://www.theverge.com/rss/index.xml"
                ),
                DefaultSource(
                    title: "Ars Technica",
                    urlString: "https://feeds.arstechnica.com/arstechnica/index"
                ),
                DefaultSource(
                    title: "TechCrunch",
                    urlString: "https://techcrunch.com/feed/"
                )
            ]
        ),
        SourceCategory(
            name: "World News",
            icon: "globe",
            iconColor: .green,
            sources: [
                DefaultSource(
                    title: "BBC News",
                    urlString: "https://feeds.bbci.co.uk/news/rss.xml"
                ),
                DefaultSource(
                    title: "NPR",
                    urlString: "https://feeds.npr.org/1001/rss.xml"
                ),
                DefaultSource(
                    title: "Associated Press",
                    urlString: "https://feedx.net/rss/ap.xml"
                )
            ]
        ),
        SourceCategory(
            name: "Science & Space",
            icon: "atom",
            iconColor: .purple,
            sources: [
                DefaultSource(
                    title: "NASA Breaking News",
                    urlString: "https://www.nasa.gov/rss/dyn/breaking_news.rss"
                ),
                DefaultSource(
                    title: "Science Daily",
                    urlString: "https://www.sciencedaily.com/rss/all.xml"
                ),
                DefaultSource(
                    title: "Space.com",
                    urlString: "https://www.space.com/feeds/all"
                )
            ]
        ),
        SourceCategory(
            name: "Apple & Design",
            icon: "apple.logo",
            iconColor: .gray,
            sources: [
                DefaultSource(
                    title: "Daring Fireball",
                    urlString: "https://daringfireball.net/feeds/main"
                ),
                DefaultSource(
                    title: "MacRumors",
                    urlString: "https://feeds.macrumors.com/MacRumors-All"
                ),
                DefaultSource(
                    title: "9to5Mac",
                    urlString: "https://9to5mac.com/feed/"
                )
            ]
        ),
        SourceCategory(
            name: "Entertainment",
            icon: "film",
            iconColor: .pink,
            sources: [
                DefaultSource(
                    title: "Variety",
                    urlString: "https://variety.com/feed/"
                ),
                DefaultSource(
                    title: "The A.V. Club",
                    urlString: "https://www.avclub.com/rss"
                ),
                DefaultSource(
                    title: "Polygon",
                    urlString: "https://www.polygon.com/rss/index.xml"
                )
            ]
        )
    ]
}
