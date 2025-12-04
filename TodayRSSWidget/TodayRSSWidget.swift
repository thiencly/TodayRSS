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

// MARK: - Shared Helpers

/// Get articles for a specific source entity
private func getArticles(for source: SourceEntity?) -> [WidgetArticle] {
    let manager = WidgetDataManager.shared

    guard let source = source else {
        return manager.allArticles()
    }

    if source.isFolder {
        return manager.articles(forFolder: source.id)
    } else {
        return manager.articles(for: source.id)
    }
}

private let sampleArticles: [WidgetArticle] = [
    WidgetArticle(
        id: "1",
        title: "Open TodayRSS app to sync your feeds",
        link: "https://todayrss.app/sync",
        summary: "Your feeds will appear here after syncing.",
        pubDate: Date(),
        thumbnailURL: nil,
        sourceTitle: "TodayRSS",
        sourceIconURL: nil
    ),
    WidgetArticle(
        id: "2",
        title: "Tap to open the app and refresh",
        link: "https://todayrss.app/sync",
        summary: "Pull down to refresh or use Sync Now in Settings.",
        pubDate: Date().addingTimeInterval(-3600),
        thumbnailURL: nil,
        sourceTitle: "TodayRSS",
        sourceIconURL: nil
    ),
    WidgetArticle(
        id: "3",
        title: "No articles synced yet",
        link: "https://todayrss.app/sync",
        summary: "Open the app to start syncing your RSS feeds.",
        pubDate: Date().addingTimeInterval(-7200),
        thumbnailURL: nil,
        sourceTitle: "TodayRSS",
        sourceIconURL: nil
    )
]

// MARK: - Time Formatter
private func formatTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
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

// MARK: - Cached Widget Image View
struct CachedWidgetImage: View {
    let thumbnailURL: URL?

    var body: some View {
        if let url = thumbnailURL,
           let image = WidgetImageCache.shared.loadImage(for: url) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [Color(.systemGray4), Color(.systemGray5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Dominant Color Helper
private func getDominantColor(for url: URL?) -> Color {
    guard let url = url else {
        return Color.black
    }

    guard let cachedData = WidgetImageCache.shared.loadImageWithColor(for: url) else {
        return Color.black
    }

    guard let uiColor = cachedData.dominantColor else {
        return Color(white: 0.15)
    }

    return Color(uiColor)
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

        for folder in config.folders {
            suggestions.append(SourceEntity(id: folder.id, displayName: "📁 \(folder.name)", isFolder: true))
        }

        for feed in config.feeds {
            suggestions.append(SourceEntity(id: feed.id, displayName: feed.title, isFolder: false))
        }

        return suggestions
    }

    func defaultResult() async -> SourceEntity? {
        nil
    }
}

// ============================================================================
// MARK: - SMALL WIDGET (and Lock Screen)
// ============================================================================

// MARK: - Small Widget Entry
struct SmallWidgetEntry: TimelineEntry {
    let date: Date
    let articles: [WidgetArticle]
    let sourceName: String?
}

// MARK: - Small Widget Intent
struct SmallWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select Source" }
    static var description: IntentDescription { "Choose a feed or folder to display" }

    @Parameter(title: "Source")
    var source: SourceEntity?
}

// MARK: - Small Widget Provider
struct SmallWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SmallWidgetEntry {
        SmallWidgetEntry(date: Date(), articles: sampleArticles, sourceName: "TodayRSS")
    }

    func snapshot(for configuration: SmallWidgetIntent, in context: Context) async -> SmallWidgetEntry {
        let articles = getArticles(for: configuration.source)
        return SmallWidgetEntry(
            date: Date(),
            articles: articles.isEmpty ? sampleArticles : articles,
            sourceName: configuration.source?.displayName ?? "All Sources"
        )
    }

    func timeline(for configuration: SmallWidgetIntent, in context: Context) async -> Timeline<SmallWidgetEntry> {
        var articles = getArticles(for: configuration.source)

        if articles.isEmpty {
            articles = sampleArticles
        }

        let entry = SmallWidgetEntry(
            date: Date(),
            articles: articles,
            sourceName: configuration.source?.displayName ?? "All Sources"
        )

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

// MARK: - Small Widget View
struct SmallWidgetView: View {
    let entry: SmallWidgetEntry

    var body: some View {
        if let article = entry.articles.first {
            let hasThumbnail = article.thumbnailImageURL != nil &&
                WidgetImageCache.shared.loadImage(for: article.thumbnailImageURL!) != nil

            if hasThumbnail {
                smallWidgetWithThumbnail(article: article)
            } else {
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
                CachedWidgetImage(thumbnailURL: article.thumbnailImageURL)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

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

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
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
                LinearGradient(
                    colors: [Color(.systemGray4), Color(.systemGray6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
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

// MARK: - Lock Screen Widget Views
struct LockScreenCircularView: View {
    let entry: SmallWidgetEntry

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
    let entry: SmallWidgetEntry

    var body: some View {
        if let article = entry.articles.first {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if let iconURL = article.sourceIconImageURL,
                       let iconImage = WidgetImageCache.shared.loadImage(for: iconURL) {
                        Image(uiImage: iconImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
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

struct LockScreenInlineView: View {
    let entry: SmallWidgetEntry

    var body: some View {
        if let article = entry.articles.first {
            Text(article.title)
        } else {
            Text("TodayRSS")
        }
    }
}

// MARK: - Small Widget Entry View
struct SmallWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: SmallWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
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

// MARK: - Small Widget Definition
struct SmallRSSWidget: Widget {
    let kind: String = "SmallRSSWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SmallWidgetIntent.self, provider: SmallWidgetProvider()) { entry in
            SmallWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .contentMarginsDisabled()
        .configurationDisplayName("TodayRSS")
        .description("Stay updated with your RSS feeds.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// ============================================================================
// MARK: - MEDIUM WIDGET
// ============================================================================

// MARK: - Medium Widget Entry
struct MediumWidgetEntry: TimelineEntry {
    let date: Date
    let leftArticle: WidgetArticle?
    let rightArticle: WidgetArticle?
}

// MARK: - Medium Widget Intent
struct MediumWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select Sources" }
    static var description: IntentDescription { "Choose feeds or folders for left and right sides" }

    @Parameter(title: "Left Source")
    var leftSource: SourceEntity?

    @Parameter(title: "Right Source")
    var rightSource: SourceEntity?
}

// MARK: - Medium Widget Provider
struct MediumWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MediumWidgetEntry {
        MediumWidgetEntry(
            date: Date(),
            leftArticle: sampleArticles[0],
            rightArticle: sampleArticles[1]
        )
    }

    func snapshot(for configuration: MediumWidgetIntent, in context: Context) async -> MediumWidgetEntry {
        let (left, right) = getLeftRightArticles(for: configuration)
        return MediumWidgetEntry(
            date: Date(),
            leftArticle: left ?? sampleArticles[0],
            rightArticle: right ?? sampleArticles[1]
        )
    }

    func timeline(for configuration: MediumWidgetIntent, in context: Context) async -> Timeline<MediumWidgetEntry> {
        let (left, right) = getLeftRightArticles(for: configuration)

        let entry = MediumWidgetEntry(
            date: Date(),
            leftArticle: left ?? sampleArticles.first,
            rightArticle: right ?? (sampleArticles.count > 1 ? sampleArticles[1] : nil)
        )

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func getLeftRightArticles(for configuration: MediumWidgetIntent) -> (WidgetArticle?, WidgetArticle?) {
        let leftArticles = getArticles(for: configuration.leftSource)
        let rightArticles = getArticles(for: configuration.rightSource)

        // If same source selected for both (or both nil), show 2 articles from that source
        if configuration.leftSource?.id == configuration.rightSource?.id {
            let allFromSource = leftArticles
            let left = allFromSource.first
            let right = allFromSource.dropFirst().first
            return (left, right)
        } else {
            // Different sources - take first article from each
            return (leftArticles.first, rightArticles.first)
        }
    }
}

// MARK: - Medium Widget View
struct MediumWidgetView: View {
    let entry: MediumWidgetEntry

    var body: some View {
        let hasAnyArticle = entry.leftArticle != nil || entry.rightArticle != nil

        if !hasAnyArticle {
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
                HStack(spacing: 0) {
                    if let article = entry.leftArticle {
                        articleCard(
                            article: article,
                            width: geo.size.width / 2,
                            height: geo.size.height
                        )
                    }

                    if let article = entry.rightArticle {
                        articleCard(
                            article: article,
                            width: geo.size.width / 2,
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
                CachedWidgetImage(thumbnailURL: article.thumbnailImageURL)
                    .frame(width: width, height: height)
                    .clipped()

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

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 3) {
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
                LinearGradient(
                    colors: [Color(.systemGray4), Color(.systemGray6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 3) {
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

// MARK: - Medium Widget Entry View
struct MediumWidgetEntryView: View {
    var entry: MediumWidgetEntry

    var body: some View {
        MediumWidgetView(entry: entry)
    }
}

// MARK: - Medium Widget Definition
struct MediumRSSWidget: Widget {
    let kind: String = "MediumRSSWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: MediumWidgetIntent.self, provider: MediumWidgetProvider()) { entry in
            MediumWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .contentMarginsDisabled()
        .configurationDisplayName("TodayRSS Dual")
        .description("Two sources side by side.")
        .supportedFamilies([.systemMedium])
    }
}

// ============================================================================
// MARK: - Widget Bundle
// ============================================================================

@main
struct TodayRSSWidgetBundle: WidgetBundle {
    var body: some Widget {
        SmallRSSWidget()
        MediumRSSWidget()
    }
}

// MARK: - Previews
#Preview("Small", as: .systemSmall) {
    SmallRSSWidget()
} timeline: {
    SmallWidgetEntry(date: Date(), articles: sampleArticles, sourceName: "TodayRSS")
}

#Preview("Medium", as: .systemMedium) {
    MediumRSSWidget()
} timeline: {
    MediumWidgetEntry(date: Date(), leftArticle: sampleArticles[0], rightArticle: sampleArticles[1])
}

#Preview("Lock Screen Rectangular", as: .accessoryRectangular) {
    SmallRSSWidget()
} timeline: {
    SmallWidgetEntry(date: Date(), articles: sampleArticles, sourceName: "TodayRSS")
}
