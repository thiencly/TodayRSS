//
//  TodayRSSWidget.swift
//  TodayRSSWidget
//
//  Widget extension for TodayRSS app
//  Data is synced from the main app via background sync
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Entry
struct NewsEntry: TimelineEntry {
    let date: Date
    let articles: [WidgetArticle]
    let sourceName: String?
    let configuration: ConfigurationAppIntent
}

// MARK: - Timeline Provider
struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NewsEntry {
        NewsEntry(
            date: Date(),
            articles: Self.sampleArticles,
            sourceName: "TodayRSS",
            configuration: ConfigurationAppIntent()
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> NewsEntry {
        // For snapshot, use cached articles
        let articles = getCachedArticles(for: configuration)
        return NewsEntry(
            date: Date(),
            articles: articles.isEmpty ? Self.sampleArticles : articles,
            sourceName: configuration.source?.displayName ?? "All Sources",
            configuration: configuration
        )
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<NewsEntry> {
        // Use cached articles from main app's background sync
        // The app syncs feeds in the background and shares data via App Group
        var articles = getCachedArticles(for: configuration)

        // Fall back to sample if no synced data yet
        if articles.isEmpty {
            articles = Self.sampleArticles
        }

        let entry = NewsEntry(
            date: Date(),
            articles: articles,
            sourceName: configuration.source?.displayName ?? "All Sources",
            configuration: configuration
        )

        // Refresh timeline every 30 minutes to pick up new synced data
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func getCachedArticles(for configuration: ConfigurationAppIntent) -> [WidgetArticle] {
        let manager = WidgetDataManager.shared

        if let source = configuration.source {
            if source.isFolder {
                return manager.articles(forFolder: source.id)
            } else {
                return manager.articles(for: source.id)
            }
        }
        return manager.allArticles()
    }

    static let sampleArticles: [WidgetArticle] = [
        WidgetArticle(
            id: "1",
            title: "Breaking: Major Tech Announcement Expected Today",
            link: "https://example.com/1",
            summary: "Industry leaders gather for what promises to be a groundbreaking reveal.",
            pubDate: Date(),
            thumbnailURL: nil,
            sourceTitle: "Tech News",
            sourceIconURL: nil
        ),
        WidgetArticle(
            id: "2",
            title: "Markets Rally on Positive Economic Data",
            link: "https://example.com/2",
            summary: "Stock indices reach new highs following employment report.",
            pubDate: Date().addingTimeInterval(-3600),
            thumbnailURL: nil,
            sourceTitle: "Finance Daily",
            sourceIconURL: nil
        ),
        WidgetArticle(
            id: "3",
            title: "New Study Reveals Surprising Health Benefits",
            link: "https://example.com/3",
            summary: "Researchers discover unexpected connections in latest findings.",
            pubDate: Date().addingTimeInterval(-7200),
            thumbnailURL: nil,
            sourceTitle: "Health Weekly",
            sourceIconURL: nil
        )
    ]
}

// MARK: - Widget Configuration Intent
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select Source" }
    static var description: IntentDescription { "Choose a feed or folder to display" }

    @Parameter(title: "Source")
    var source: SourceEntity?
}

// MARK: - Source Entity for Intent
struct SourceEntity: AppEntity, Identifiable, Hashable {
    let id: String
    let displayName: String
    let isFolder: Bool

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Source"
    }

    static var defaultQuery = SourceQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SourceEntity, rhs: SourceEntity) -> Bool {
        lhs.id == rhs.id
    }
}

struct SourceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SourceEntity] {
        let config = WidgetDataManager.shared.loadSourceConfig()
        var results: [SourceEntity] = []

        for id in identifiers {
            if let feed = config.feeds.first(where: { $0.id == id }) {
                results.append(SourceEntity(id: feed.id, displayName: feed.title, isFolder: false))
            } else if let folder = config.folders.first(where: { $0.id == id }) {
                results.append(SourceEntity(id: folder.id, displayName: folder.name, isFolder: true))
            }
        }
        return results
    }

    func suggestedEntities() async throws -> [SourceEntity] {
        let config = WidgetDataManager.shared.loadSourceConfig()
        var suggestions: [SourceEntity] = []

        // Add folders first
        for folder in config.folders {
            suggestions.append(SourceEntity(id: folder.id, displayName: "📁 \(folder.name)", isFolder: true))
        }

        // Then add individual feeds
        for feed in config.feeds {
            suggestions.append(SourceEntity(id: feed.id, displayName: feed.title, isFolder: false))
        }

        return suggestions
    }

    func defaultResult() async -> SourceEntity? {
        nil // Show all sources by default
    }
}

// MARK: - Time Formatter
private func formatTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
}

// MARK: - Cached Widget Image View
/// Loads images from the shared App Group cache instead of network
/// Does NOT use AsyncImage because widgets have strict image size limits
struct CachedWidgetImage: View {
    let thumbnailURL: URL?

    var body: some View {
        if let url = thumbnailURL,
           let image = WidgetImageCache.shared.loadImage(for: url) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // Show gradient placeholder - don't use AsyncImage (causes "image too large" errors)
            LinearGradient(
                colors: [Color(.systemGray4), Color(.systemGray5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Dominant Color Helper
/// Gets the dominant color for a thumbnail URL, or returns a default dark color
private func getDominantColor(for url: URL?) -> Color {
    guard let url = url else {
        return Color.black // No URL provided
    }

    guard let cachedData = WidgetImageCache.shared.loadImageWithColor(for: url) else {
        return Color.black // Image not in cache
    }

    guard let uiColor = cachedData.dominantColor else {
        // Image exists but color extraction failed - use dark gray
        return Color(white: 0.15)
    }

    return Color(uiColor)
}

// MARK: - Small Widget View (Apple News Style)
struct SmallWidgetView: View {
    let entry: NewsEntry

    var body: some View {
        if let article = entry.articles.first {
            let hasThumbnail = article.thumbnailImageURL != nil &&
                WidgetImageCache.shared.loadImage(for: article.thumbnailImageURL!) != nil

            if hasThumbnail {
                // Image-focused layout with thumbnail
                smallWidgetWithThumbnail(article: article)
            } else {
                // Text-focused layout with favicon-based gradient
                smallWidgetTextOnly(article: article)
            }
        } else {
            VStack {
                Text("No Articles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func smallWidgetWithThumbnail(article: WidgetArticle) -> some View {
        let gradientColor = getDominantColor(for: article.thumbnailImageURL)

        GeometryReader { geo in
            ZStack {
                // Thumbnail background - fills entire widget
                CachedWidgetImage(thumbnailURL: article.thumbnailImageURL)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // Bottom gradient - uses dominant color from thumbnail
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: gradientColor.opacity(0.15), location: 0.35),
                            .init(color: gradientColor.opacity(0.7), location: 0.55),
                            .init(color: gradientColor.opacity(0.95), location: 0.7),
                            .init(color: gradientColor, location: 0.8),
                            .init(color: gradientColor, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.75)
                }

                // Content
                VStack(alignment: .leading, spacing: 0) {
                    // Source label and time at top
                    HStack(spacing: 4) {
                        // Source favicon
                        if let iconURL = article.sourceIconImageURL,
                           let iconImage = WidgetImageCache.shared.loadImage(for: iconURL) {
                            Image(uiImage: iconImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }

                        Text(article.sourceTitle ?? entry.sourceName ?? "TodayRSS")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)

                        if let pubDate = article.pubDate {
                            Text("·")
                                .font(.system(size: 11))
                            Text(formatTime(pubDate))
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                    Spacer()

                    // Headline
                    Text(article.title)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
                .padding(18)
            }
        }
        .widgetURL(article.linkURL)
    }

    @ViewBuilder
    private func smallWidgetTextOnly(article: WidgetArticle) -> some View {
        GeometryReader { geo in
            ZStack {
                // Gray gradient background
                LinearGradient(
                    colors: [Color(.systemGray4), Color(.systemGray6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Content - source at top, centered headline
                VStack(alignment: .leading, spacing: 0) {
                    // Source label and time at top
                    HStack(spacing: 4) {
                        // Source favicon
                        if let iconURL = article.sourceIconImageURL,
                           let iconImage = WidgetImageCache.shared.loadImage(for: iconURL) {
                            Image(uiImage: iconImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }

                        Text(article.sourceTitle ?? entry.sourceName ?? "TodayRSS")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)

                        if let pubDate = article.pubDate {
                            Text("·")
                                .font(.system(size: 11))
                            Text(formatTime(pubDate))
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .foregroundStyle(.secondary)

                    Spacer()

                    // Headline - centered, scales down for long titles
                    Text(article.title)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(6)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(18)
            }
        }
        .widgetURL(article.linkURL)
    }
}

// MARK: - Medium Widget View (Apple News Style)
struct MediumWidgetView: View {
    let entry: NewsEntry

    var body: some View {
        if entry.articles.isEmpty {
            HStack {
                Spacer()
                VStack {
                    Image(systemName: "newspaper")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Articles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        } else {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    // First article
                    if let firstArticle = entry.articles.first {
                        articleCard(
                            article: firstArticle,
                            width: (geo.size.width - 2) / 2,
                            height: geo.size.height
                        )
                    }

                    // Second article
                    if entry.articles.count > 1 {
                        articleCard(
                            article: entry.articles[1],
                            width: (geo.size.width - 2) / 2,
                            height: geo.size.height
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func articleCard(article: WidgetArticle, width: CGFloat, height: CGFloat) -> some View {
        let hasThumbnail = article.thumbnailImageURL != nil &&
            WidgetImageCache.shared.loadImage(for: article.thumbnailImageURL!) != nil

        if hasThumbnail {
            articleCardWithThumbnail(article: article, width: width, height: height)
        } else {
            articleCardTextOnly(article: article, width: width, height: height)
        }
    }

    @ViewBuilder
    private func articleCardWithThumbnail(article: WidgetArticle, width: CGFloat, height: CGFloat) -> some View {
        let gradientColor = getDominantColor(for: article.thumbnailImageURL)

        Link(destination: article.linkURL ?? URL(string: "todayrss://")!) {
            ZStack {
                // Thumbnail background - fills card
                CachedWidgetImage(thumbnailURL: article.thumbnailImageURL)
                    .frame(width: width, height: height)
                    .clipped()

                // Bottom gradient - uses dominant color from thumbnail
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: gradientColor.opacity(0.15), location: 0.35),
                            .init(color: gradientColor.opacity(0.7), location: 0.55),
                            .init(color: gradientColor.opacity(0.95), location: 0.7),
                            .init(color: gradientColor, location: 0.8),
                            .init(color: gradientColor, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: height * 0.7)
                }

                // Content
                VStack(alignment: .leading, spacing: 0) {
                    // Source label and time at top
                    HStack(spacing: 3) {
                        // Source favicon
                        if let iconURL = article.sourceIconImageURL,
                           let iconImage = WidgetImageCache.shared.loadImage(for: iconURL) {
                            Image(uiImage: iconImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 10, height: 10)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }

                        Text(article.sourceTitle ?? "News")
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)

                        if let pubDate = article.pubDate {
                            Text("·")
                                .font(.system(size: 10))
                            Text(formatTime(pubDate))
                                .font(.system(size: 9, weight: .medium))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                    Spacer()

                    // Headline
                    Text(article.title)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
                .padding(14)
            }
            .frame(width: width, height: height)
        }
    }

    @ViewBuilder
    private func articleCardTextOnly(article: WidgetArticle, width: CGFloat, height: CGFloat) -> some View {
        Link(destination: article.linkURL ?? URL(string: "todayrss://")!) {
            ZStack {
                // Gray gradient background
                LinearGradient(
                    colors: [Color(.systemGray4), Color(.systemGray6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Content - source at top, centered headline
                VStack(alignment: .leading, spacing: 0) {
                    // Source label and time at top
                    HStack(spacing: 3) {
                        // Source favicon
                        if let iconURL = article.sourceIconImageURL,
                           let iconImage = WidgetImageCache.shared.loadImage(for: iconURL) {
                            Image(uiImage: iconImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 10, height: 10)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }

                        Text(article.sourceTitle ?? "News")
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)

                        if let pubDate = article.pubDate {
                            Text("·")
                                .font(.system(size: 10))
                            Text(formatTime(pubDate))
                                .font(.system(size: 9, weight: .medium))
                        }
                    }
                    .foregroundStyle(.secondary)

                    Spacer()

                    // Headline - centered, scales down for long titles
                    Text(article.title)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(5)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(14)
            }
            .frame(width: width, height: height)
        }
    }
}

// MARK: - Lock Screen Widget Views
struct LockScreenCircularView: View {
    let entry: NewsEntry

    var body: some View {
        if let article = entry.articles.first,
           let iconURL = article.sourceIconImageURL,
           let iconImage = WidgetImageCache.shared.loadImage(for: iconURL) {
            ZStack {
                AccessoryWidgetBackground()
                Image(uiImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Text("RSS")
                    .font(.system(size: 12, weight: .bold))
            }
        }
    }
}

struct LockScreenRectangularView: View {
    let entry: NewsEntry

    var body: some View {
        if let article = entry.articles.first {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    // Source favicon (bigger)
                    if let iconURL = article.sourceIconImageURL,
                       let iconImage = WidgetImageCache.shared.loadImage(for: iconURL) {
                        Image(uiImage: iconImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    // Relative day + time (e.g., "Today, 10:55 AM")
                    if let pubDate = article.pubDate {
                        Text(formatRelativeDateTime(pubDate))
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.secondary)

                Text(article.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(article.linkURL)
        } else {
            Text("TodayRSS")
                .font(.system(size: 10))
        }
    }
}

/// Format date as relative day + time (e.g., "Today, 10:55 AM")
private func formatRelativeDateTime(_ date: Date) -> String {
    let calendar = Calendar.current
    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "h:mm a"
    let timeString = timeFormatter.string(from: date)

    if calendar.isDateInToday(date) {
        return "Today, \(timeString)"
    } else if calendar.isDateInYesterday(date) {
        return "Yesterday, \(timeString)"
    } else {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE" // Day name (e.g., "Monday")
        let dayString = dayFormatter.string(from: date)
        return "\(dayString), \(timeString)"
    }
}

struct LockScreenInlineView: View {
    let entry: NewsEntry

    var body: some View {
        if let article = entry.articles.first {
            Text(article.title)
        } else {
            Text("TodayRSS")
        }
    }
}

// MARK: - Main Widget View
struct TodayRSSWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .accessoryCircular:
            LockScreenCircularView(entry: entry)
        case .accessoryRectangular:
            LockScreenRectangularView(entry: entry)
        case .accessoryInline:
            LockScreenInlineView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget Definition
struct TodayRSSWidget: Widget {
    let kind: String = "TodayRSSWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            TodayRSSWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .contentMarginsDisabled() // Remove default widget margins for edge-to-edge images
        .configurationDisplayName("TodayRSS")
        .description("Stay updated with your RSS feeds.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Widget Bundle
@main
struct TodayRSSWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayRSSWidget()
    }
}

// MARK: - Previews
#Preview("Small", as: .systemSmall) {
    TodayRSSWidget()
} timeline: {
    NewsEntry(date: Date(), articles: Provider.sampleArticles, sourceName: "TodayRSS", configuration: ConfigurationAppIntent())
}

#Preview("Medium", as: .systemMedium) {
    TodayRSSWidget()
} timeline: {
    NewsEntry(date: Date(), articles: Provider.sampleArticles, sourceName: "TodayRSS", configuration: ConfigurationAppIntent())
}

#Preview("Lock Screen Rectangular", as: .accessoryRectangular) {
    TodayRSSWidget()
} timeline: {
    NewsEntry(date: Date(), articles: Provider.sampleArticles, sourceName: "TodayRSS", configuration: ConfigurationAppIntent())
}
