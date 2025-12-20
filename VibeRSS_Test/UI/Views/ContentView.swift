import SwiftUI
import UIKit
import WidgetKit

// MARK: - Hero Card Height Preference Key

private struct HeroCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Shimmer Modifier

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { proxy in
                    let width = max(1, proxy.size.width)
                    let height = max(1, proxy.size.height)

                    let primary = LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.0), location: 0.00),
                            .init(color: Color.white.opacity(0.08), location: 0.18),
                            .init(color: Color.white.opacity(0.35), location: 0.50),
                            .init(color: Color.white.opacity(0.08), location: 0.82),
                            .init(color: Color.white.opacity(0.0), location: 1.00)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    let tint = LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.blue.opacity(0.00), location: 0.00),
                            .init(color: Color.blue.opacity(0.10), location: 0.45),
                            .init(color: Color.purple.opacity(0.10), location: 0.55),
                            .init(color: Color.purple.opacity(0.00), location: 1.00)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    ZStack {
                        Rectangle()
                            .fill(tint)
                            .rotationEffect(.degrees(18))
                            .frame(width: width * 0.78, height: height * 1.8)
                            .offset(x: width * (phase - 0.12))
                            .blur(radius: 8)
                            .blendMode(.screen)

                        Rectangle()
                            .fill(primary)
                            .rotationEffect(.degrees(20))
                            .frame(width: width * 0.64, height: height * 1.7)
                            .offset(x: width * phase)
                            .blur(radius: 2)
                            .blendMode(.screen)
                    }
                }
                .clipped()
                .allowsHitTesting(false)
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
    }
}

extension View {
    @ViewBuilder
    func shimmer(if condition: Bool) -> some View {
        if condition {
            self.modifier(Shimmer())
        } else {
            self
        }
    }
}

// MARK: - Plain Disclosure Style (hides default chevron)

private struct PlainDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                configuration.label
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

// MARK: - Sidebar Hero Card

private struct SidebarHeroCardView: View {
    struct Entry: Identifiable, Hashable, Codable {
        // Use link as stable identity to prevent animation jank when entries update
        var id: URL { link }
        let source: Source
        let title: String
        let oneLine: String
        let link: URL
        var isNew: Bool
        let pubDate: Date?
    }

    let entries: [Entry]
    var previousEntries: [Entry] = []
    var showDiagonalReveal: Bool = false
    var isLoading: Bool = false
    var isCollapsed: Bool = false
    var tintColor: Color = .blue
    var onTapLink: ((URL) -> Void)? = nil
    var onToggleCollapse: (() -> Void)? = nil
    var onDiagonalRevealComplete: (() -> Void)? = nil

    private var newArticleCount: Int {
        entries.filter { $0.isNew }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("At a Glance")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)

                // Loading indicator when generating summaries
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                // New articles badge
                if newArticleCount > 0 && !isLoading {
                    Text("\(newArticleCount) new")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(tintColor))
                }

                Spacer()

                // Only show chevron when there are entries to show
                if !entries.isEmpty || isLoading {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        .animation(.snappy(duration: 0.25), value: isCollapsed)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !entries.isEmpty {
                    onToggleCollapse?()
                }
            }

            // Only show entries when not collapsed and has entries
            if !isCollapsed && !entries.isEmpty {
                // Entries with diagonal reveal animation
                Group {
                    if showDiagonalReveal && !previousEntries.isEmpty {
                        // Diagonal reveal animation from old entries to new entries
                        AIDiagonalReveal(
                            showNew: .constant(true),
                            fadeDuration: 0.2,
                            revealDuration: 0.25,
                            flashDuration: 0.35,
                            onComplete: {
                                onDiagonalRevealComplete?()
                            }
                        ) {
                            // Old content - previous entries
                            entriesContentView(from: previousEntries)
                        } newContent: {
                            // New content - current entries
                            entriesContentView(from: entries)
                        }
                    } else {
                        // Use entriesContentView for consistent styling with diagonal reveal
                        entriesContentView(from: entries)
                    }
                }
            }
        }
        .padding(14)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.snappy(duration: 0.3), value: isCollapsed)
        .animation(.snappy(duration: 0.3), value: entries.isEmpty)
        .background {
            // Only show glow when there are new articles
            if newArticleCount > 0 || isLoading {
                PriorityNotificationGlow(isActive: true, cornerRadius: 20)
                AppleIntelligenceGlow(cornerRadius: 20, isActive: isLoading, showIdle: newArticleCount > 0)
            }
        }
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeholderRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2))
                    .frame(width: 20, height: 20)
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2))
                    .frame(width: 120, height: 12)
                Spacer()
            }
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2))
                .frame(height: 10)
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2))
                .frame(width: 180, height: 10)
        }
        .redacted(reason: .placeholder)
        .shimmer(if: true)
    }

    /// Helper to render entries content for use in diagonal reveal animation
    @ViewBuilder
    private func entriesContentView(from entryList: [Entry]) -> some View {
        let sorted = entryList.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        VStack(alignment: .leading, spacing: 12) {
            ForEach(sorted) { entry in
                staticEntryRow(entry)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }

    /// Static entry row for diagonal reveal (no shimmer/gradient animations)
    @ViewBuilder
    private func staticEntryRow(_ entry: Entry) -> some View {
        let displayText = entry.oneLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? entry.title : entry.oneLine

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                FeedIconView(iconURL: entry.source.iconURL)
                    .frame(width: 20, height: 20)
                Text(entry.source.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer()
            }
            Text(displayText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2...3)  // Minimum 2 lines, max 3 lines
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)  // ~2 lines minimum
        }
        .contentShape(Rectangle())
        .onTapGesture { onTapLink?(entry.link) }
    }
}

// MARK: - Article Collector for Widget Sync

private actor ArticleCollector {
    private var articles: [UUID: [FeedItem]] = [:]

    func store(feedID: UUID, items: [FeedItem]) {
        articles[feedID] = items
    }

    func getAll() -> [UUID: [FeedItem]] {
        return articles
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var store = FeedStore()
    @State private var selectedSource: Source?
    @State private var showingAdd = false
    @State private var showingAddFolder = false
    @State private var movingSource: Source?
    @State private var showingMoveDialog = false
    @State private var renamingSource: Source?
    @State private var renameText: String = ""
    @State private var renamingFolder: Folder?
    @State private var renameFolderText: String = ""
    @State private var refreshID = UUID()
    @State private var isRefreshingAll = false
    @State private var refreshTotal: Int = 0
    @State private var refreshCompleted: Int = 0
    @State private var refreshArticlesCachedThisRun: Int = 0
    @State private var refreshArticlesSkippedThisRun: Int = 0
    @State private var currentRefreshRunID = UUID()
    @State private var cooldownUntil: Date? = nil
    @State private var heroWebLink: WebLink? = nil
    @AppStorage("lastRefreshAllDate") private var lastRefreshAllDate: Double = 0
    @AppStorage("areSourcesCollapsed") private var areSourcesCollapsed: Bool = false
    @AppStorage("areFoldersCollapsed") private var areFoldersCollapsed: Bool = false
    @AppStorage("showLatestView") private var showLatestView: Bool = true
    @AppStorage("showTodayView") private var showTodayView: Bool = true
    @AppStorage("appTint") private var appTint: String = AppTint.blue.rawValue
    @State private var showingSettings: Bool = false

    @Environment(\.scenePhase) private var scenePhase

    // At a Glance settings
    @AppStorage("atAGlanceCount") private var atAGlanceCount: Int = 3
    @AppStorage("atAGlanceAutoExpand") private var atAGlanceAutoExpand: Bool = true

    @State private var heroEntries: [SidebarHeroCardView.Entry] = []
    @State private var isLoadingHero: Bool = false
    @State private var pendingHeroRefresh: Bool = false
    @State private var previousHeroEntries: [SidebarHeroCardView.Entry] = []
    @State private var showDiagonalReveal: Bool = false
    @State private var isHeroCollapsed: Bool = true
    @State private var lastHeroUpdateDate: Date? = nil
    private let heroUpdateCooldown: TimeInterval = 300 // 5 minutes
    private let heroCacheKey = "viberss.heroEntries"
    private let seenLinksKey = "viberss.heroSeenLinks"
    @State private var isInitialLoad: Bool = true
    @State private var sidebarRefreshTrigger: UUID = UUID()
    @State private var isSourceListVisible: Bool = true
    @State private var showingNewsReel: Bool = false

    private let refreshService = FeedService()

    private let maxConcurrentFeeds = 2
    private let maxPrefetchPerFeed = 6
    private let maxConcurrentArticlePrefetch = 1
    private let interBatchDelayNs: UInt64 = 150_000_000

    private let feedGate = ConcurrencyGate(limit: 2)
    private let articleGate = ConcurrencyGate(limit: 3)

    private func refreshAll() async {
        let runID = currentRefreshRunID
        let feeds = store.feeds
        let snapshotFeeds = feeds
        if Task.isCancelled { return }
        await MainActor.run {
            refreshTotal = feeds.count
            refreshCompleted = 0
            refreshArticlesCachedThisRun = 0
            refreshArticlesSkippedThisRun = 0
        }

        // Collect articles for widget sync using actor for thread safety
        let articleCollector = ArticleCollector()

        await withTaskGroup(of: Void.self) { group in
            for feed in snapshotFeeds {
                group.addTask {
                    if Task.isCancelled { return }
                    await feedGate.withPermit {
                        defer {
                            Task { @MainActor in
                                if isRefreshingAll && runID == currentRefreshRunID {
                                    refreshCompleted += 1
                                }
                            }
                        }
                        do {
                            var items = try await refreshService.loadItems(from: feed.url)

                            // Add source info to items for widget
                            for i in items.indices {
                                items[i].sourceID = feed.id
                                items[i].sourceTitle = feed.title
                                items[i].sourceIconURL = feed.iconURL
                            }

                            // Store for widget sync
                            await articleCollector.store(feedID: feed.id, items: Array(items.prefix(10)))
                            try Task.checkCancellation()
                            if Task.isCancelled { return }

                            let limited = Array(items.prefix(maxPrefetchPerFeed))

                            let batchSize = max(1, maxConcurrentArticlePrefetch)
                            var index = 0
                            while index < limited.count {
                                if Task.isCancelled { return }
                                let end = min(index + batchSize, limited.count)
                                let batch = limited[index..<end]

                                await withTaskGroup(of: Void.self) { inner in
                                    for item in batch {
                                        inner.addTask {
                                            if Task.isCancelled { return }
                                            if Task.isCancelled { return }
                                            await articleGate.withPermit {
                                                if await ArticleTextCache.shared.cachedText(for: item.link) != nil {
                                                    await MainActor.run { refreshArticlesSkippedThisRun += 1 }
                                                    return
                                                }
                                                if Task.isCancelled { return }
                                                do {
                                                    try Task.checkCancellation()
                                                    try await withTimeout(5.0) {
                                                        try Task.checkCancellation()
                                                        let html = try await ArticleSummarizer.shared.fetchHTML(url: item.link)
                                                        try Task.checkCancellation()
                                                        let limitedHTML = String(html.prefix(160_000))
                                                        let text = ArticleSummarizer.shared.extractReadableText(from: limitedHTML)
                                                        try Task.checkCancellation()
                                                        if !text.isEmpty {
                                                            await ArticleTextCache.shared.storeText(text, for: item.link)
                                                            await MainActor.run { refreshArticlesCachedThisRun += 1 }
                                                        }
                                                    }
                                                } catch {
                                                    // Ignore per-item errors
                                                }
                                            }
                                        }
                                    }
                                    for await _ in inner { }
                                    if Task.isCancelled { return }
                                }

                                try? await Task.sleep(nanoseconds: interBatchDelayNs)
                                try Task.checkCancellation()
                                if Task.isCancelled { return }
                                index = end
                            }
                        } catch {
                            // Ignore individual failures
                        }
                    }
                }
            }
            for await _ in group { }
        }

        // Sync articles to widget
        let articlesToSync = await articleCollector.getAll()
        if !articlesToSync.isEmpty {
            // Download thumbnails and favicons for widget (top 3 per feed)
            await downloadThumbnailsForWidget(articlesByFeed: articlesToSync)

            await MainActor.run {
                WidgetUpdater.shared.updateArticles(articlesByFeed: articlesToSync)
                // Reload widget timelines (explicit kinds for lock screen widgets)
                WidgetCenter.shared.reloadTimelines(ofKind: "SmallRSSWidget")
                WidgetCenter.shared.reloadTimelines(ofKind: "MediumRSSWidget")
            }
        }
    }

    private func downloadThumbnailsForWidget(articlesByFeed: [UUID: [FeedItem]]) async {
        var thumbnailURLs: [URL] = []
        var faviconURLs: Set<URL> = []

        for (_, articles) in articlesByFeed {
            // Sort by date to get newest articles first
            let sorted = articles.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            for article in sorted.prefix(5) {
                if let url = article.thumbnailURL {
                    thumbnailURLs.append(url)
                }
                if let iconURL = article.sourceIconURL {
                    faviconURLs.insert(iconURL)
                }
            }
        }

        // Download thumbnails (increased limit from 20 to 40)
        if !thumbnailURLs.isEmpty {
            await withTaskGroup(of: Void.self) { group in
                for url in thumbnailURLs.prefix(40) {
                    group.addTask {
                        _ = await WidgetImageCache.shared.downloadAndCache(from: url)
                    }
                }
            }
        }

        // Download favicons
        if !faviconURLs.isEmpty {
            await withTaskGroup(of: Void.self) { group in
                for url in faviconURLs {
                    group.addTask {
                        _ = await WidgetImageCache.shared.downloadAndCache(from: url)
                    }
                }
            }
        }
    }

    private func withTimeout<T>(_ seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            guard let result = try await group.next() else {
                group.cancelAll()
                throw URLError(.unknown)
            }
            group.cancelAll()
            return result
        }
    }

    private func relativeTimeString(since date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        let minutes = (seconds + 59) / 60
        if minutes < 60 { return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago" }
        let hours = (minutes + 59) / 60
        if hours < 24 { return hours == 1 ? "1 hour ago" : "\(hours) hours ago" }
        let days = (hours + 23) / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    private func oneSentence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let idx = trimmed.firstIndex(where: { [".", "!", "?"].contains($0) }) {
            return String(trimmed[..<trimmed.index(after: idx)])
        }
        let softCap = 280
        if trimmed.count > softCap {
            let capIndex = trimmed.index(trimmed.startIndex, offsetBy: softCap, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            if let spaceIdx = trimmed[..<capIndex].lastIndex(of: " ") {
                return String(trimmed[..<spaceIdx])
            }
        }
        return trimmed
    }

    private func saveHeroEntriesToCache() {
        // Encode JSON off main thread to prevent UI freeze
        let entries = heroEntries
        Task.detached(priority: .utility) {
            do {
                // Only cache entries that have valid summaries
                let validEntries = entries.filter { !$0.oneLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let data = try JSONEncoder().encode(validEntries)
                UserDefaults.standard.set(data, forKey: self.heroCacheKey)

                // Only save links that are already marked as seen (isNew = false)
                // This preserves blue dots during the session - they only clear on app restart
                let seenLinks = validEntries.filter { !$0.isNew }.map { $0.link.absoluteString }
                let linksData = try JSONEncoder().encode(seenLinks)
                UserDefaults.standard.set(linksData, forKey: self.seenLinksKey)
            } catch {}
        }
    }

    /// Save all current hero entry links as "seen" - call when app goes to background
    private func markAllHeroEntriesAsSeen() {
        // Update in-memory entries to clear blue dots immediately
        for i in heroEntries.indices {
            heroEntries[i].isNew = false
        }

        // Persist to UserDefaults
        let entries = heroEntries
        Task.detached(priority: .utility) {
            do {
                let validEntries = entries.filter { !$0.oneLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let allLinks = validEntries.map { $0.link.absoluteString }
                let linksData = try JSONEncoder().encode(allLinks)
                UserDefaults.standard.set(linksData, forKey: self.seenLinksKey)
            } catch {}
        }
    }

    private func loadHeroEntriesFromCache() {
        // Load synchronously on main thread to ensure entries are available before loadHeroEntries()
        guard let data = UserDefaults.standard.data(forKey: heroCacheKey) else { return }
        guard let decoded = try? JSONDecoder().decode([SidebarHeroCardView.Entry].self, from: data) else { return }
        // Filter out entries with empty summaries - they'll be regenerated
        // Mark all cached entries as NOT new (they were already seen before app was killed)
        var filtered = decoded.filter { !$0.oneLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for i in filtered.indices {
            filtered[i].isNew = false
        }
        heroEntries = filtered
    }

    private func loadSeenLinks() -> Set<URL> {
        guard let data = UserDefaults.standard.data(forKey: seenLinksKey),
              let links = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(links.compactMap { URL(string: $0) })
    }

    @MainActor private func loadHeroEntries(forceReveal: Bool = false, bypassCooldown: Bool = false) async {
        // If already loading, mark for refresh after current load completes
        if isLoadingHero {
            pendingHeroRefresh = true
            return
        }

        // Check cooldown - don't update more than once every 5 minutes (unless initial load or bypassed)
        if !bypassCooldown && !isInitialLoad, let lastUpdate = lastHeroUpdateDate {
            let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
            if timeSinceLastUpdate < heroUpdateCooldown {
                // Within cooldown period, keep collapsed and skip update
                return
            }
        }

        // Show loading indicator (glow will appear on collapsed card)
        isLoadingHero = true
        pendingHeroRefresh = false

        // Fetch from ALL sources
        let feeds = store.feeds

        // Use persisted seen links (survives app restart)
        let previouslySeenLinks = loadSeenLinks()

        // Keep existing entries indexed by link for comparison
        let existingEntriesByLink: [URL: SidebarHeroCardView.Entry] = Dictionary(
            heroEntries.map { ($0.link, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Step 1: Fetch latest article from each feed in parallel
        var feedArticles: [(feed: Feed, article: FeedItem)] = []
        await withTaskGroup(of: (Feed, FeedItem)?.self) { group in
            for feed in feeds {
                group.addTask {
                    do {
                        let items = try await self.refreshService.loadItems(from: feed.url)
                        guard let latest = items.sorted(by: { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }).first else {
                            return nil
                        }
                        return (feed, latest)
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                if let r = result { feedArticles.append(r) }
            }
        }

        // Sort by most recent first
        feedArticles.sort { ($0.article.pubDate ?? .distantPast) > ($1.article.pubDate ?? .distantPast) }

        // Only keep NEW articles (not seen before)
        var newArticles: [(feed: Feed, article: FeedItem)] = []
        for (feed, article) in feedArticles {
            if !previouslySeenLinks.contains(article.link) {
                newArticles.append((feed, article))
                // Limit to atAGlanceCount
                if newArticles.count >= atAGlanceCount {
                    break
                }
            }
        }

        let hasNewArticles = !newArticles.isEmpty

        // If no new articles, mark all existing entries as not new and collapse
        if !hasNewArticles {
            // Mark all existing entries as not new
            for i in heroEntries.indices {
                heroEntries[i].isNew = false
            }
            isLoadingHero = false
            isInitialLoad = false
            lastHeroUpdateDate = Date()

            // Collapse the card (user can tap to expand and see prior articles)
            withAnimation(.snappy(duration: 0.3)) {
                isHeroCollapsed = true
            }

            saveHeroEntriesToCache()

            if pendingHeroRefresh {
                pendingHeroRefresh = false
                Task { await loadHeroEntries(bypassCooldown: true) }
            }
            return
        }

        // Store current entries for diagonal reveal when expanding
        let shouldTriggerDiagonalReveal = forceReveal || (!heroEntries.isEmpty && atAGlanceAutoExpand)
        if shouldTriggerDiagonalReveal {
            previousHeroEntries = heroEntries
        }

        // Step 2: Generate summaries for new articles
        var newEntries: [SidebarHeroCardView.Entry] = []
        await withTaskGroup(of: SidebarHeroCardView.Entry?.self) { group in
            for (feed, article) in newArticles {
                let existingEntry = existingEntriesByLink[article.link]

                group.addTask {
                    // Check if we already have a valid summary
                    if let existing = existingEntry, !existing.oneLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return SidebarHeroCardView.Entry(
                            source: existing.source,
                            title: existing.title,
                            oneLine: existing.oneLine,
                            link: existing.link,
                            isNew: true,
                            pubDate: existing.pubDate
                        )
                    }

                    // Generate new summary
                    let minSummaryLength = 50
                    var summary = ""
                    for attempt in 1...3 {
                        summary = await ArticleSummarizer.shared.fastHeroSummary(url: article.link, articleText: article.summary) ?? ""
                        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed.count >= minSummaryLength {
                            break
                        }
                        if attempt < 3 {
                            try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
                        }
                    }

                    let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedSummary.isEmpty || trimmedSummary.count < minSummaryLength {
                        return nil
                    }

                    return SidebarHeroCardView.Entry(
                        source: feed,
                        title: article.title,
                        oneLine: summary,
                        link: article.link,
                        isNew: true,
                        pubDate: article.pubDate
                    )
                }
            }

            for await entry in group {
                if let entry = entry {
                    newEntries.append(entry)
                }
            }
        }

        // Sort entries by date
        newEntries.sort { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }

        // Update heroEntries
        heroEntries = newEntries
        isLoadingHero = false
        lastHeroUpdateDate = Date()

        // Handle reveal and expand based on context
        if !newEntries.isEmpty && !isInitialLoad {
            // Trigger diagonal reveal animation if we have previous entries to transition from
            if shouldTriggerDiagonalReveal && !previousHeroEntries.isEmpty {
                showDiagonalReveal = true
            }

            // Only expand if card is collapsed and auto-expand is on
            if isHeroCollapsed && atAGlanceAutoExpand {
                HapticManager.shared.success()
                withAnimation(.snappy(duration: 0.3)) {
                    isHeroCollapsed = false
                }
            }
        }

        saveHeroEntriesToCache()
        isInitialLoad = false

        // If a refresh was requested while loading, run again
        if pendingHeroRefresh {
            pendingHeroRefresh = false
            Task { await loadHeroEntries(bypassCooldown: true) }
        }
    }

    /// Fetch latest articles for all sources to populate sidebar blue dots on app launch
    @MainActor private func refreshLatestArticlesForSidebar() async {
        let feeds = store.feeds
        let service = refreshService

        await withTaskGroup(of: (UUID, [URL]).self) { group in
            for feed in feeds {
                group.addTask {
                    do {
                        let items = try await service.loadItems(from: feed.url)
                        let urls = items.prefix(20).map { $0.link }
                        return (feed.id, urls)
                    } catch {
                        return (feed.id, [])
                    }
                }
            }
            for await (feedID, urls) in group {
                if !urls.isEmpty {
                    // Use immediate save so sidebar refresh sees the updated data
                    await ArticleReadStateManager.shared.updateLatestArticlesImmediate(for: feedID, urls: urls)
                }
            }
        }

        // Refresh sidebar to show blue dots
        sidebarRefreshTrigger = UUID()
    }

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        let folderFeeds = store.feeds.filter { $0.folderID == folder.id }
        let sourceIDs = folderFeeds.map { $0.id }
        let hasNewArticles = ArticleReadStateManager.folderHasNewArticlesSync(folder.id, sourceIDs: sourceIDs)

        NavigationLink {
            FolderDetailView(folder: folder, refreshID: refreshID)
                .environmentObject(store)
        } label: {
            HStack {
                Label(folder.name, systemImage: "folder")
                if hasNewArticles {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
                Spacer()
                Text("\(folderFeeds.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .contextMenu {
            Button {
                renameFolderText = folder.name
                renamingFolder = folder
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                store.removeFolder(folder)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }

        // Show sources under this folder when expanded
        if !areFoldersCollapsed {
            ForEach(folderFeeds) { source in
                folderSourceRow(source)
            }
        }
    }

    @ViewBuilder
    private func folderSourceRow(_ source: Feed) -> some View {
        let hasNewArticles = ArticleReadStateManager.sourceHasNewArticlesSync(source.id)

        NavigationLink {
            FeedDetailView(source: source, refreshID: refreshID)
        } label: {
            HStack(spacing: 12) {
                FeedIconView(iconURL: source.iconURL)
                Text(source.title)
                if hasNewArticles {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .padding(.leading, 20)
        .contextMenu {
            Button {
                renameText = source.title
                renamingSource = source
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                store.assign(source, to: nil)
            } label: {
                Label("Remove from Section", systemImage: "folder.badge.minus")
            }
            Button(role: .destructive) {
                if let idx = store.feeds.firstIndex(where: { $0.id == source.id }) {
                    store.feeds.remove(at: idx)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // Navigation state for UIKit sidebar
    @State private var navigationDestination: SidebarDestination?

    // MARK: - Navigation Handling

    private func handleNavigation(_ destination: SidebarDestination) {
        navigationDestination = destination
    }

    // MARK: - Context Menu Builders

    private func createFolderContextMenu(_ folder: Folder) -> UIMenu? {
        let renameAction = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in
            renameFolderText = folder.name
            renamingFolder = folder
        }

        let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
            store.removeFolder(folder)
        }

        return UIMenu(children: [renameAction, deleteAction])
    }

    private func createFeedContextMenu(_ feed: Feed) -> UIMenu? {
        var actions: [UIMenuElement] = []

        let refreshIconAction = UIAction(title: "Refresh Icon", image: UIImage(systemName: "arrow.triangle.2.circlepath")) { _ in
            Task { await store.refreshIcon(for: feed) }
        }
        actions.append(refreshIconAction)

        let renameAction = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in
            renameText = feed.title
            renamingSource = feed
        }
        actions.append(renameAction)

        // Move to Section submenu
        var moveActions: [UIAction] = []
        for folder in store.folders {
            let isCurrentFolder = feed.folderID == folder.id
            let action = UIAction(
                title: folder.name,
                image: UIImage(systemName: isCurrentFolder ? "checkmark" : "folder")
            ) { _ in
                store.assign(feed, to: folder)
            }
            moveActions.append(action)
        }

        if feed.folderID != nil {
            let removeAction = UIAction(title: "Remove from Section", image: UIImage(systemName: "folder.badge.minus")) { _ in
                store.assign(feed, to: nil)
            }
            moveActions.append(removeAction)
        }

        if !moveActions.isEmpty {
            let moveMenu = UIMenu(title: "Move to Section", image: UIImage(systemName: "folder.badge.plus"), children: moveActions)
            actions.append(moveMenu)
        }

        let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
            if let idx = store.feeds.firstIndex(where: { $0.id == feed.id }) {
                store.feeds.remove(at: idx)
                if selectedSource?.id == feed.id {
                    selectedSource = store.feeds.first
                }
            }
        }
        actions.append(deleteAction)

        return UIMenu(children: actions)
    }

    @ViewBuilder private var sidebar: some View {
        // UIKit-based collapsible list with native animations
        CollapsibleSidebarList(
            folders: store.folders,
            feeds: store.feeds,
            showLatestView: showLatestView,
            showTodayView: showTodayView,
            savedCount: SavedArticlesManager.shared.savedArticles.count,
            sectionsExpanded: Binding(
                get: { !areFoldersCollapsed },
                set: { areFoldersCollapsed = !$0 }
            ),
            sourcesExpanded: Binding(
                get: { !areSourcesCollapsed },
                set: { areSourcesCollapsed = !$0 }
            ),
            tintColor: AppTint(rawValue: appTint)?.uiColor ?? .systemBlue,
            onNavigate: { destination in
                handleNavigation(destination)
            },
            onFolderContextMenu: { folder in
                createFolderContextMenu(folder)
            },
            onFeedContextMenu: { feed in
                createFeedContextMenu(feed)
            }
        )
        .ignoresSafeArea()
        .id(sidebarRefreshTrigger)
        .navigationTitle("TodayRSS")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            // At a Glance card as overlay - expands on top of the list
            if isLoadingHero || !heroEntries.isEmpty {
                SidebarHeroCardView(
                    entries: heroEntries,
                    previousEntries: previousHeroEntries,
                    showDiagonalReveal: showDiagonalReveal,
                    isLoading: isLoadingHero,
                    isCollapsed: isHeroCollapsed,
                    tintColor: AppTint(rawValue: appTint)?.color ?? .blue,
                    onTapLink: { url in
                        heroWebLink = WebLink(url: url)
                    },
                    onToggleCollapse: {
                        HapticManager.shared.click()
                        withAnimation(.snappy(duration: 0.3)) {
                            isHeroCollapsed.toggle()
                        }
                    },
                    onDiagonalRevealComplete: {
                        showDiagonalReveal = false
                        previousHeroEntries = []
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showingAdd = true } label: {
                            Image(systemName: "plus")
                        }

                        Menu {
                            Button { showingAddFolder = true } label: {
                                Label("New Section", systemImage: "folder.badge.plus")
                            }

                            Divider()

                            Button {
                                triggerRefreshAll()
                            } label: {
                                Label("Refresh All Feeds", systemImage: "arrow.clockwise")
                            }
                            .disabled(isRefreshingAll)

                            Divider()

                            Button {
                                // Clear cache but keep showing old entries until new ones are ready
                                UserDefaults.standard.removeObject(forKey: heroCacheKey)
                                Task {
                                    await ArticleSummarizer.shared.clearHeroSummaries()
                                    await loadHeroEntries(forceReveal: true)
                                }
                            } label: {
                                Label("Clear At a Glance", systemImage: "sun.horizon")
                            }
                            Button(role: .destructive) {
                                Task { await ArticleSummarizer.shared.clearArticleSummaries() }
                            } label: {
                                Label("Clear All Summaries", systemImage: "trash")
                            }
                        } label: {
                            if isRefreshingAll {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                let tintColor = AppTint(rawValue: appTint)?.color ?? .blue

                Button {
                    HapticManager.shared.click()
                    showingNewsReel = true
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(tintColor)
                        .clipShape(Circle())
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
            .sheet(isPresented: $showingAdd) {
                AddFeedView { newSource in
                    store.feeds.append(newSource)
                    selectedSource = newSource
                }
                .environmentObject(store)
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showingAddFolder) {
                AddFolderView { newFolder in
                    store.folders.append(newFolder)
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $heroWebLink) { w in
                ArticleReaderView(url: w.url, articleTitle: w.title, articleDate: w.date, thumbnailURL: w.thumbnailURL, sourceIconURL: w.sourceIconURL, sourceTitle: w.sourceTitle)
            }
            .confirmationDialog("Move to Section", isPresented: $showingMoveDialog, presenting: movingSource) { source in
                ForEach(store.folders) { folder in
                    let isCurrentFolder = source.folderID == folder.id
                    Button(isCurrentFolder ? "\(folder.name) ✓" : folder.name) {
                        store.assign(source, to: folder)
                    }
                }
                if source.folderID != nil {
                    Button("Remove from Section", role: .destructive) {
                        store.assign(source, to: nil)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { source in
                Text("Choose a section for \(source.title)")
            }
            .alert("Rename Source", isPresented: Binding(
                get: { renamingSource != nil },
                set: { if !$0 { renamingSource = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {
                    renamingSource = nil
                }
                Button("Save") {
                    if let source = renamingSource,
                       let idx = store.feeds.firstIndex(where: { $0.id == source.id }) {
                        store.feeds[idx].title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    renamingSource = nil
                }
            } message: {
                Text("Enter a new name for this source")
            }
            .alert("Rename Section", isPresented: Binding(
                get: { renamingFolder != nil },
                set: { if !$0 { renamingFolder = nil } }
            )) {
                TextField("Name", text: $renameFolderText)
                Button("Cancel", role: .cancel) {
                    renamingFolder = nil
                }
                Button("Save") {
                    if let folder = renamingFolder {
                        let newName = renameFolderText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !newName.isEmpty {
                            store.renameFolder(folder, to: newName)
                        }
                    }
                    renamingFolder = nil
                }
            } message: {
                Text("Enter a new name for this section")
            }
        .overlay(alignment: .bottom) {
            // Refresh progress overlay at bottom
            if isRefreshingAll {
                HStack(spacing: 10) {
                    ProgressView(value: Double(refreshCompleted), total: Double(refreshTotal))
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Refreshing feeds: \(refreshCompleted)/\(refreshTotal)")
                        Text("Cached (new): \(refreshArticlesCachedThisRun)")
                        Text("Skipped (already cached): \(refreshArticlesSkippedThisRun)")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.secondary.opacity(0.2))
                )
                .padding(.bottom, 8)
                .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $showingNewsReel) {
            NewsReelView()
                .environmentObject(store)
        }
    }

    private func triggerRefreshAll() {
        if let until = cooldownUntil, until > Date() { return }
        guard !isRefreshingAll else { return }
        isRefreshingAll = true
        currentRefreshRunID = UUID()
        Task {
            await feedGate.reset()
            await articleGate.reset()
            await MainActor.run {
                refreshCompleted = 0
                refreshTotal = store.feeds.count
                refreshArticlesCachedThisRun = 0
                refreshArticlesSkippedThisRun = 0
            }
            do {
                try await withTimeout(30.0) { await refreshAll() }
            } catch {
                await feedGate.reset()
                await articleGate.reset()
            }
            await MainActor.run {
                refreshID = UUID()
                Task { await loadHeroEntries() }
                isRefreshingAll = false
                refreshCompleted = 0
                refreshTotal = 0
                refreshArticlesCachedThisRun = 0
                refreshArticlesSkippedThisRun = 0
                lastRefreshAllDate = Date().timeIntervalSince1970
                cooldownUntil = Date().addingTimeInterval(1.5)
            }
        }
    }

    @ViewBuilder private var detailView: some View {
        // Show placeholder by default - FeedDetailView only created when navigated to
        // This matches AllArticlesView behavior and avoids first-load lag
        ContentPlaceholder()
    }

    var body: some View {
        NavigationSplitView {
            NavigationStack {
                sidebar
                    .navigationDestination(item: $navigationDestination) { destination in
                        switch destination {
                        case .latest:
                            CurrentView(refreshID: refreshID)
                                .environmentObject(store)
                        case .today:
                            AllArticlesView(refreshID: refreshID)
                                .environmentObject(store)
                        case .saved:
                            SavedArticlesView()
                        case .folder(let id):
                            if let folder = store.folders.first(where: { $0.id == id }) {
                                FolderDetailView(folder: folder, refreshID: refreshID)
                                    .environmentObject(store)
                            }
                        case .feed(let id):
                            if let feed = store.feeds.first(where: { $0.id == id }) {
                                FeedDetailView(source: feed, refreshID: refreshID)
                            }
                        }
                    }
            }
        } detail: {
            detailView
        }
        .onAppear {
            selectedSource = store.feeds.first
            store.backfillIcons()
            loadHeroEntriesFromCache()
            // Start collapsed - will auto-expand if there are new articles
            isHeroCollapsed = true
            Task {
                // Small delay to allow child views (article list) to register their appearance first
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                // Only generate hero summaries if source list is visible
                if isSourceListVisible {
                    await loadHeroEntries()
                }
                // Fetch latest articles to show blue dots on sources/folders
                await refreshLatestArticlesForSidebar()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Refresh sidebar to update blue dot indicators when app becomes active
                sidebarRefreshTrigger = UUID()
                // Only generate hero summaries if source list is visible
                // This prevents generating summaries while on article list view
                if isSourceListVisible {
                    Task { await loadHeroEntries() }
                }
            } else if phase == .background {
                // Collapse card when app goes to background
                // So it's already collapsed on hot start (no animation visible to user)
                isHeroCollapsed = true
                // Mark all current hero entries as "seen" when app goes to background
                // This clears blue dots on next launch if no new articles
                markAllHeroEntriesAsSeen()
            }
        }
        .onChange(of: store.feeds) { _, _ in
            // Only generate hero summaries if source list is visible
            if isSourceListVisible {
                Task { await loadHeroEntries() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReturnToSourceList)) { _ in
            // User returned to source list - mark as visible and load hero entries
            isSourceListVisible = true
            // Refresh sidebar to update blue dot indicators
            sidebarRefreshTrigger = UUID()
            // Load hero entries now that source list is visible
            // Don't mark as seen first - let user see blue dots for new articles
            Task { await loadHeroEntries() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .backgroundSyncCompleted)) { _ in
            // Refresh hero entries and sidebar after background sync completes
            // Only if source list is visible
            sidebarRefreshTrigger = UUID()
            if isSourceListVisible {
                Task { await loadHeroEntries() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didNavigateToArticleList)) { _ in
            // User navigated to an article list view - mark source list as not visible
            isSourceListVisible = false
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let didReturnToSourceList = Notification.Name("didReturnToSourceList")
    static let didNavigateToArticleList = Notification.Name("didNavigateToArticleList")
    static let backgroundSyncCompleted = Notification.Name("backgroundSyncCompleted")
}
