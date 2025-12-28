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

// MARK: - Apple Intelligence Colors for Widget
private enum WidgetAIColors {
    static let colors: [Color] = [
        Color(red: 0.74, green: 0.51, blue: 0.95),  // Purple #BC82F3
        Color(red: 0.96, green: 0.73, blue: 0.92),  // Pink #F5B9EA
        Color(red: 0.55, green: 0.62, blue: 1.0),   // Blue #8D9FFF
        Color(red: 1.0, green: 0.40, blue: 0.47),   // Coral #FF6778
        Color(red: 1.0, green: 0.73, blue: 0.44),   // Orange #FFBA71
        Color(red: 0.67, green: 0.43, blue: 0.93),  // Violet #AA6EEE
        Color(red: 0.78, green: 0.53, blue: 1.0),   // Light Purple #C686FF
    ]
}

/// Static glow background matching the News Reel style
private struct WidgetGlowBackground: View {
    var body: some View {
        ZStack {
            // Dark base
            Color.black

            // Soft gradient glow layer - mimics NewsReelGlow
            LinearGradient(
                colors: WidgetAIColors.colors,
                startPoint: UnitPoint(x: 0.2, y: 0.3),
                endPoint: UnitPoint(x: 0.8, y: 0.7)
            )
            .blur(radius: 30)
            .opacity(0.6)
        }
    }
}

// MARK: - Shared Helpers

/// Get articles for a specific source entity
private func getArticles(for source: SourceEntity?) -> [WidgetArticle] {
    let manager = WidgetDataManager.shared

    // If no source selected or "All Sources" selected, return all articles
    guard let source = source, source.id != "all-sources" else {
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
            WidgetGlowBackground()
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
    private static let allSourcesID = "all-sources"

    func entities(for identifiers: [String]) async throws -> [SourceEntity] {
        let config = WidgetDataManager.shared.loadSourceConfig()
        var results: [SourceEntity] = []

        for id in identifiers {
            // Check for "All Sources" special ID
            if id == Self.allSourcesID {
                results.append(SourceEntity(id: Self.allSourcesID, displayName: "All Sources", isFolder: false))
                continue
            }

            // Use case-insensitive comparison for UUID strings
            let normalizedID = id.uppercased()

            if let feed = config.feeds.first(where: { $0.id.uppercased() == normalizedID }) {
                results.append(SourceEntity(id: feed.id, displayName: feed.title, isFolder: false))
            } else if let folder = config.folders.first(where: { $0.id.uppercased() == normalizedID }) {
                results.append(SourceEntity(id: folder.id, displayName: folder.name, isFolder: true))
            } else {
                // Entity not found in config - this can happen if:
                // 1. Config hasn't been synced from main app yet
                // 2. The folder/feed was deleted
                // Return a placeholder entity to preserve the user's selection
                // and allow the widget to retry when config is synced
                //
                // Try to determine if this was a folder by checking if any feeds reference it
                let isFolderID = config.feeds.contains { $0.folderID?.uppercased() == normalizedID }
                if isFolderID {
                    // This ID is referenced as a folderID, so it's a folder
                    results.append(SourceEntity(id: id, displayName: "📁 Folder", isFolder: true))
                } else {
                    // Unknown - assume it's a feed
                    results.append(SourceEntity(id: id, displayName: "Source", isFolder: false))
                }
            }
        }
        return results
    }

    func suggestedEntities() async throws -> [SourceEntity] {
        let config = WidgetDataManager.shared.loadSourceConfig()
        var suggestions: [SourceEntity] = []

        // Add "All Sources" as the first option
        suggestions.append(SourceEntity(id: Self.allSourcesID, displayName: "📰 All Sources", isFolder: false))

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

// MARK: - Widget Configuration Sync
/// Saves widget configurations to App Group so main app knows which feeds to sync
private func saveWidgetConfiguration(sourceIDs: [String]) {
    guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

    // Get existing configurations
    var allSourceIDs = Set(sharedDefaults.stringArray(forKey: "widgetConfiguredSourceIDs") ?? [])

    // Add new source IDs
    for id in sourceIDs {
        allSourceIDs.insert(id)
    }

    sharedDefaults.set(Array(allSourceIDs), forKey: "widgetConfiguredSourceIDs")
}

// MARK: - Small Widget Provider
struct SmallWidgetProvider: AppIntentTimelineProvider {
    /// Interval between timeline entries for home screen widgets (15 minutes)
    private let homeScreenEntryInterval: TimeInterval = 15 * 60
    /// Interval between timeline entries for lock screen widgets (30 minutes)
    private let lockScreenEntryInterval: TimeInterval = 30 * 60
    /// Maximum number of timeline entries for home screen widgets
    private let homeScreenMaxEntries = 6
    /// Maximum number of timeline entries for lock screen widgets
    /// More entries = less frequent reload requests = better for iOS budget
    private let lockScreenMaxEntries = 6

    /// Check if this is a lock screen widget family
    private func isLockScreenWidget(_ family: WidgetFamily) -> Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            return false
        }
    }

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
        // Save configuration to App Group so main app knows which feeds to sync
        if let source = configuration.source {
            saveWidgetConfiguration(sourceIDs: [source.id])
        } else {
            saveWidgetConfiguration(sourceIDs: ["all"])
        }

        var articles = getArticles(for: configuration.source)
        let sourceName = configuration.source?.displayName ?? "All Sources"

        if articles.isEmpty {
            articles = sampleArticles
        }

        let now = Date()
        let isLockScreen = isLockScreenWidget(context.family)

        // Lock screen widgets have stricter refresh budgets from iOS
        // Use fewer entries and longer intervals to conserve budget
        let maxEntries = isLockScreen ? lockScreenMaxEntries : homeScreenMaxEntries
        let entryInterval = isLockScreen ? lockScreenEntryInterval : homeScreenEntryInterval

        // Create timeline entries to cycle through articles
        var entries: [SmallWidgetEntry] = []
        let articleCount = min(articles.count, maxEntries)

        for i in 0..<articleCount {
            let entryDate = now.addingTimeInterval(Double(i) * entryInterval)
            // Rotate articles so each entry shows a different article first
            let rotatedArticles = Array(articles.dropFirst(i)) + Array(articles.prefix(i))
            entries.append(SmallWidgetEntry(
                date: entryDate,
                articles: rotatedArticles,
                sourceName: sourceName
            ))
        }

        // If no entries were created (shouldn't happen), create at least one
        if entries.isEmpty {
            entries.append(SmallWidgetEntry(
                date: now,
                articles: articles,
                sourceName: sourceName
            ))
        }

        // For lock screen widgets, use a longer refresh interval to conserve budget
        // For home screen widgets, use .atEnd to refresh after all entries displayed
        let refreshPolicy: TimelineReloadPolicy
        if isLockScreen {
            // Refresh lock screen widgets every 2 hours to conserve budget
            refreshPolicy = .after(now.addingTimeInterval(2 * 60 * 60))
        } else {
            refreshPolicy = .atEnd
        }

        return Timeline(entries: entries, policy: refreshPolicy)
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
        .widgetURL(article.deepLinkURL ?? article.linkURL)
    }

    @ViewBuilder
    private func smallWidgetTextOnly(article: WidgetArticle) -> some View {
        GeometryReader { geo in
            ZStack {
                WidgetGlowBackground()

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
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)

                    Spacer()

                    Text(article.title)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(6)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)

                    Spacer()
                }
                .padding(18)
            }
        }
        .widgetURL(article.deepLinkURL ?? article.linkURL)
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
            .widgetURL(article.deepLinkURL ?? article.linkURL)
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
    /// Interval between timeline entries (15 minutes)
    private let entryInterval: TimeInterval = 15 * 60
    /// Maximum number of timeline entries to create
    private let maxEntries = 6

    func placeholder(in context: Context) -> MediumWidgetEntry {
        MediumWidgetEntry(
            date: Date(),
            leftArticle: sampleArticles[0],
            rightArticle: sampleArticles[1]
        )
    }

    func snapshot(for configuration: MediumWidgetIntent, in context: Context) async -> MediumWidgetEntry {
        let (left, right) = getLeftRightArticles(for: configuration, offset: 0)
        return MediumWidgetEntry(
            date: Date(),
            leftArticle: left ?? sampleArticles[0],
            rightArticle: right ?? sampleArticles[1]
        )
    }

    func timeline(for configuration: MediumWidgetIntent, in context: Context) async -> Timeline<MediumWidgetEntry> {
        // Save configuration to App Group so main app knows which feeds to sync
        var sourceIDs: [String] = []
        if let left = configuration.leftSource {
            sourceIDs.append(left.id)
        } else {
            sourceIDs.append("all")
        }
        if let right = configuration.rightSource {
            sourceIDs.append(right.id)
        } else {
            sourceIDs.append("all")
        }
        saveWidgetConfiguration(sourceIDs: sourceIDs)

        // Create multiple timeline entries to cycle through article pairs
        // This allows the widget to show different articles without consuming refresh budget
        var entries: [MediumWidgetEntry] = []
        let now = Date()

        // Determine how many unique pairs we can show
        let leftArticles = getArticles(for: configuration.leftSource)
        let rightArticles = getArticles(for: configuration.rightSource)
        let sameSource = configuration.leftSource?.id == configuration.rightSource?.id

        // Calculate max rotations based on available articles
        let availablePairs: Int
        if sameSource {
            // Same source: we need 2 articles per entry, so max pairs = articles / 2
            availablePairs = max(1, leftArticles.count / 2)
        } else {
            // Different sources: we can rotate each independently
            availablePairs = max(1, max(leftArticles.count, rightArticles.count))
        }

        let entryCount = min(availablePairs, maxEntries)

        for i in 0..<entryCount {
            let entryDate = now.addingTimeInterval(Double(i) * entryInterval)
            let (left, right) = getLeftRightArticles(for: configuration, offset: i)

            entries.append(MediumWidgetEntry(
                date: entryDate,
                leftArticle: left ?? sampleArticles.first,
                rightArticle: right ?? (sampleArticles.count > 1 ? sampleArticles[1] : nil)
            ))
        }

        // If no entries were created, create at least one
        if entries.isEmpty {
            let (left, right) = getLeftRightArticles(for: configuration, offset: 0)
            entries.append(MediumWidgetEntry(
                date: now,
                leftArticle: left ?? sampleArticles.first,
                rightArticle: right ?? (sampleArticles.count > 1 ? sampleArticles[1] : nil)
            ))
        }

        // Use .atEnd policy - after all entries are displayed, system will request new timeline
        // Combined with multiple entries, this provides automatic article rotation with minimal budget use
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func getLeftRightArticles(for configuration: MediumWidgetIntent, offset: Int) -> (WidgetArticle?, WidgetArticle?) {
        let leftArticles = getArticles(for: configuration.leftSource)
        let rightArticles = getArticles(for: configuration.rightSource)

        // If same source selected for both (or both nil), show 2 articles from that source
        if configuration.leftSource?.id == configuration.rightSource?.id {
            let allFromSource = leftArticles
            // Rotate by offset * 2 to show different pairs
            let startIndex = (offset * 2) % max(1, allFromSource.count)
            let left = allFromSource.indices.contains(startIndex) ? allFromSource[startIndex] : nil
            let right = allFromSource.indices.contains(startIndex + 1) ? allFromSource[startIndex + 1] : nil
            return (left, right)
        } else {
            // Different sources - rotate each independently
            let leftIndex = offset % max(1, leftArticles.count)
            let rightIndex = offset % max(1, rightArticles.count)
            let left = leftArticles.indices.contains(leftIndex) ? leftArticles[leftIndex] : nil
            let right = rightArticles.indices.contains(rightIndex) ? rightArticles[rightIndex] : nil
            return (left, right)
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

        Link(destination: article.deepLinkURL ?? article.linkURL ?? URL(string: "todayrss://")!) {
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
        Link(destination: article.deepLinkURL ?? article.linkURL ?? URL(string: "todayrss://")!) {
            ZStack {
                WidgetGlowBackground()

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
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)

                    Spacer()

                    Text(article.title)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(5)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)

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
// MARK: - MEDIUM SINGLE WIDGET (1 article, fills entire widget)
// ============================================================================

// MARK: - Medium Single Widget Entry
struct MediumSingleWidgetEntry: TimelineEntry {
    let date: Date
    let articles: [WidgetArticle]
    let sourceName: String?
}

// MARK: - Medium Single Widget Intent
struct MediumSingleWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select Source" }
    static var description: IntentDescription { "Choose a feed or folder to display" }

    @Parameter(title: "Source")
    var source: SourceEntity?
}

// MARK: - Medium Single Widget Provider
struct MediumSingleWidgetProvider: AppIntentTimelineProvider {
    /// Interval between timeline entries (15 minutes)
    private let entryInterval: TimeInterval = 15 * 60
    /// Maximum number of timeline entries
    private let maxEntries = 6

    func placeholder(in context: Context) -> MediumSingleWidgetEntry {
        MediumSingleWidgetEntry(date: Date(), articles: sampleArticles, sourceName: "TodayRSS")
    }

    func snapshot(for configuration: MediumSingleWidgetIntent, in context: Context) async -> MediumSingleWidgetEntry {
        let articles = getArticles(for: configuration.source)
        return MediumSingleWidgetEntry(
            date: Date(),
            articles: articles.isEmpty ? sampleArticles : articles,
            sourceName: configuration.source?.displayName ?? "All Sources"
        )
    }

    func timeline(for configuration: MediumSingleWidgetIntent, in context: Context) async -> Timeline<MediumSingleWidgetEntry> {
        // Save configuration to App Group so main app knows which feeds to sync
        if let source = configuration.source, source.id != "all-sources" {
            saveWidgetConfiguration(sourceIDs: [source.id])
        } else {
            saveWidgetConfiguration(sourceIDs: ["all"])
        }

        var articles = getArticles(for: configuration.source)
        let sourceName = configuration.source?.displayName ?? "All Sources"

        if articles.isEmpty {
            articles = sampleArticles
        }

        let now = Date()

        // Create timeline entries to cycle through articles
        var entries: [MediumSingleWidgetEntry] = []
        let articleCount = min(articles.count, maxEntries)

        for i in 0..<articleCount {
            let entryDate = now.addingTimeInterval(Double(i) * entryInterval)
            // Rotate articles so each entry shows a different article first
            let rotatedArticles = Array(articles.dropFirst(i)) + Array(articles.prefix(i))
            entries.append(MediumSingleWidgetEntry(
                date: entryDate,
                articles: rotatedArticles,
                sourceName: sourceName
            ))
        }

        // If no entries were created, create at least one
        if entries.isEmpty {
            entries.append(MediumSingleWidgetEntry(
                date: now,
                articles: articles,
                sourceName: sourceName
            ))
        }

        return Timeline(entries: entries, policy: .atEnd)
    }
}

// MARK: - Medium Single Widget View
struct MediumSingleWidgetView: View {
    let entry: MediumSingleWidgetEntry

    var body: some View {
        if let article = entry.articles.first {
            let hasThumbnail = article.thumbnailImageURL != nil &&
                WidgetImageCache.shared.loadImage(for: article.thumbnailImageURL!) != nil

            if hasThumbnail {
                mediumSingleWithThumbnail(article: article)
            } else {
                mediumSingleTextOnly(article: article)
            }
        } else {
            VStack {
                Image(systemName: "newspaper")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No Articles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func mediumSingleWithThumbnail(article: WidgetArticle) -> some View {
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
                            .init(color: gradientColor.opacity(0.1), location: 0.3),
                            .init(color: gradientColor.opacity(0.6), location: 0.5),
                            .init(color: gradientColor.opacity(0.9), location: 0.65),
                            .init(color: gradientColor, location: 0.75),
                            .init(color: gradientColor, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.65)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if let iconURL = article.sourceIconImageURL,
                           let iconImage = WidgetImageCache.shared.loadImage(for: iconURL) {
                            Image(uiImage: iconImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }

                        Text(article.sourceTitle ?? entry.sourceName ?? "TodayRSS")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)

                        if let pubDate = article.pubDate {
                            Text("·")
                                .font(.system(size: 13))
                            Text(formatTime(pubDate))
                                .font(.system(size: 12, weight: .medium))
                        }

                        Spacer()
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                    Spacer()

                    Text(article.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                }
                .padding(20)
            }
        }
        .widgetURL(article.deepLinkURL ?? article.linkURL)
    }

    @ViewBuilder
    private func mediumSingleTextOnly(article: WidgetArticle) -> some View {
        GeometryReader { geo in
            ZStack {
                WidgetGlowBackground()

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        if let iconURL = article.sourceIconImageURL,
                           let iconImage = WidgetImageCache.shared.loadImage(for: iconURL) {
                            Image(uiImage: iconImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }

                        Text(article.sourceTitle ?? entry.sourceName ?? "TodayRSS")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)

                        if let pubDate = article.pubDate {
                            Text("·")
                                .font(.system(size: 13))
                            Text(formatTime(pubDate))
                                .font(.system(size: 12, weight: .medium))
                        }

                        Spacer()
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)

                    Spacer()

                    Text(article.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)

                    if !article.summary.isEmpty {
                        Text(article.summary)
                            .font(.system(size: 13, weight: .regular))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    }

                    Spacer()
                }
                .padding(20)
            }
        }
        .widgetURL(article.deepLinkURL ?? article.linkURL)
    }
}

// MARK: - Medium Single Widget Entry View
struct MediumSingleWidgetEntryView: View {
    var entry: MediumSingleWidgetEntry

    var body: some View {
        MediumSingleWidgetView(entry: entry)
    }
}

// MARK: - Medium Single Widget Definition
struct MediumSingleRSSWidget: Widget {
    let kind: String = "MediumSingleRSSWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: MediumSingleWidgetIntent.self, provider: MediumSingleWidgetProvider()) { entry in
            MediumSingleWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .contentMarginsDisabled()
        .configurationDisplayName("TodayRSS Featured")
        .description("One article, full size display.")
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
        MediumSingleRSSWidget()
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

#Preview("Medium Single", as: .systemMedium) {
    MediumSingleRSSWidget()
} timeline: {
    MediumSingleWidgetEntry(date: Date(), articles: sampleArticles, sourceName: "TodayRSS")
}
