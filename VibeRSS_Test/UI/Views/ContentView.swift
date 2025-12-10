import SwiftUI
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
    var expectedCount: Int = 3
    var isUpdating: Bool = false
    var isCollapsed: Bool = false
    var loadingSourceIDs: Set<UUID> = []
    var gradientRevealLinks: Set<URL> = []  // Entries that should show gradient reveal animation
    var onTapLink: ((URL) -> Void)? = nil
    var onToggleCollapse: (() -> Void)? = nil
    var onGradientComplete: ((URL) -> Void)? = nil

    private var sortedEntries: [Entry] {
        entries.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }

    private var visibleEntryCount: Int {
        isCollapsed ? 1 : expectedCount
    }

    private var visibleEntries: [Entry] {
        let sorted = sortedEntries
        return Array(sorted.prefix(visibleEntryCount))
    }

    private var remainingPlaceholderCount: Int {
        if isCollapsed {
            return entries.isEmpty ? 1 : 0
        } else {
            // Show placeholders for entries not yet loaded
            return max(0, expectedCount - entries.count)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    RainbowGlowSymbol(systemName: "sparkles", font: .caption, subtle: true)
                    Text("Today Highlights")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .animation(.snappy(duration: 0.25), value: isCollapsed)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onToggleCollapse?()
                }

                Group {
                    if entries.isEmpty {
                        // No entries yet - show all placeholders
                        ForEach(0..<visibleEntryCount, id: \.self) { _ in
                            placeholderRow
                        }
                    } else {
                        // Show loaded entries
                        ForEach(visibleEntries) { entry in
                            entryRow(entry)
                        }
                        // Show shimmer placeholders only while still loading
                        if !isCollapsed && isUpdating && remainingPlaceholderCount > 0 {
                            ForEach(0..<remainingPlaceholderCount, id: \.self) { _ in
                                placeholderRow
                            }
                        }
                    }
                }
                .animation(nil, value: entries.count)  // Disable animation for entry count changes
            }
            .animation(.snappy(duration: 0.25), value: isCollapsed)
        }
        .padding(16)
        .background(
            ZStack {
                // Inner ambient glow
                SiriGlow(cornerRadius: 22, opacity: 0.25)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                .blendMode(.overlay)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        // Apple Intelligence glow effect (idle state)
        .background(
            AppleIntelligenceGlow(cornerRadius: 22, isActive: false)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.2), value: isUpdating)
    }

    @ViewBuilder
    private func entryRow(_ entry: Entry) -> some View {
        let isLoadingSummary = loadingSourceIDs.contains(entry.source.id)
        let showGradient = gradientRevealLinks.contains(entry.link)
        let displayText = entry.oneLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? entry.title : entry.oneLine

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                FeedIconView(iconURL: entry.source.iconURL)
                    .frame(width: 20, height: 20)
                Text(entry.source.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                if entry.isNew {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("New article")
                }
                Spacer()
            }

            if isLoadingSummary {
                // Shimmer placeholder while generating summary
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 11)
                        .shimmer(if: true)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 160, height: 11)
                        .shimmer(if: true)
                }
            } else if showGradient {
                // Text with gradient overlay that fades away
                GradientRevealText(
                    text: displayText,
                    font: .footnote,
                    foregroundStyle: .secondary,
                    gradientDuration: 1.0,
                    onComplete: {
                        onGradientComplete?(entry.link)
                    }
                )
            } else {
                // Static text
                Text(displayText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTapLink?(entry.link) }
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
    @State private var showingSettings: Bool = false

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("heroCollapsedOnLaunch") private var heroCollapsedOnLaunch: Bool = false

    @State private var heroEntries: [SidebarHeroCardView.Entry] = []
    @State private var isLoadingHero: Bool = false
    @State private var pendingHeroRefresh: Bool = false
    @State private var loadingSummarySourceIDs: Set<UUID> = []
    @State private var gradientRevealLinks: Set<URL> = []
    @State private var heroCardHeight: CGFloat = 200
    @State private var isHeroCollapsed: Bool = false
    @AppStorage("heroSourceIDs") private var heroSourceIDsData: Data = Data()
    private let heroCacheKey = "viberss.heroEntries"
    private let seenLinksKey = "viberss.heroSeenLinks"
    @State private var isInitialLoad: Bool = true
    @State private var sidebarRefreshTrigger: UUID = UUID()

    private var heroSourceIDs: Set<UUID> {
        (try? JSONDecoder().decode(Set<UUID>.self, from: heroSourceIDsData)) ?? []
    }

    private func saveHeroSourceIDs(_ ids: Set<UUID>) {
        heroSourceIDsData = (try? JSONEncoder().encode(ids)) ?? Data()
        // Sync to iCloud
        let idStrings = ids.map { $0.uuidString }
        iCloudSyncManager.shared.saveHeroSourceIDs(idStrings)
    }

    private func loadHeroSourceIDsFromiCloud() {
        if let cloudIDs = iCloudSyncManager.shared.loadHeroSourceIDs() {
            let uuids = Set(cloudIDs.compactMap { UUID(uuidString: $0) })
            if !uuids.isEmpty && heroSourceIDs.isEmpty {
                // Only load from cloud if local is empty
                saveHeroSourceIDs(uuids)
            }
        }
    }

    private func toggleHeroSource(_ source: Source) {
        var ids = heroSourceIDs
        if ids.contains(source.id) {
            ids.remove(source.id)
            // Immediately remove the entry from heroEntries for instant UI feedback
            heroEntries.removeAll { $0.source.id == source.id }
        } else if ids.count < 3 {
            ids.insert(source.id)
        }
        saveHeroSourceIDs(ids)
        Task { await loadHeroEntries() }
    }

    private func isHeroSource(_ source: Source) -> Bool {
        heroSourceIDs.contains(source.id)
    }

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

    @MainActor private func loadHeroEntries() async {
        // If already loading, mark for refresh after current load completes
        if isLoadingHero {
            pendingHeroRefresh = true
            return
        }
        // Only show loading indicator if we don't have entries yet (initial load)
        // This prevents UI jank when refreshing with existing content
        let showLoadingState = heroEntries.isEmpty
        if showLoadingState {
            isLoadingHero = true
        }
        pendingHeroRefresh = false

        let selectedIDs = heroSourceIDs
        let feeds = store.feeds.filter { selectedIDs.contains($0.id) }

        // Use persisted seen links (survives app restart) merged with entries already marked as seen
        var previouslySeenLinks = loadSeenLinks()
        for entry in heroEntries where !entry.isNew {
            previouslySeenLinks.insert(entry.link)
        }

        // Keep existing entries as fallback (indexed by source ID)
        let existingEntriesBySource: [UUID: SidebarHeroCardView.Entry] = Dictionary(
            heroEntries.map { ($0.source.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Step 1: Fetch all feeds in parallel (fast - just RSS parsing)
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

        // Step 2: Determine which sources need new summaries
        var sourcesNeedingNewSummary: Set<UUID> = []
        var articleByFeedID: [UUID: (feed: Feed, article: FeedItem)] = [:]

        for (feed, article) in feedArticles {
            articleByFeedID[feed.id] = (feed, article)
            let existingEntry = existingEntriesBySource[feed.id]
            if existingEntry?.link != article.link {
                sourcesNeedingNewSummary.insert(feed.id)
            }
        }

        // If any sources have new articles, show shimmer on ALL sources to hide reordering
        let hasAnyNewArticles = !sourcesNeedingNewSummary.isEmpty
        if hasAnyNewArticles {
            for feed in feeds {
                loadingSummarySourceIDs.insert(feed.id)
            }
        }

        // Build entries map starting with existing
        var entriesBySourceID: [UUID: SidebarHeroCardView.Entry] = existingEntriesBySource
        var processedSourceIDs: Set<UUID> = []

        // Process all feeds concurrently
        await withTaskGroup(of: (UUID, SidebarHeroCardView.Entry?, URL?, Bool).self) { group in
            for (feed, article) in feedArticles {
                let isNew = !previouslySeenLinks.contains(article.link)
                let existingEntry = existingEntriesBySource[feed.id]
                let needsNewSummary = sourcesNeedingNewSummary.contains(feed.id)

                group.addTask {
                    if needsNewSummary {
                        // Generate new summary with retry on failure
                        // Minimum 50 chars to avoid very short/useless summaries
                        let minSummaryLength = 50
                        var summary = ""
                        for attempt in 1...3 {
                            summary = await ArticleSummarizer.shared.fastHeroSummary(url: article.link, articleText: article.summary) ?? ""
                            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty && trimmed.count >= minSummaryLength {
                                break
                            }
                            // Wait before retry (increasing delay)
                            if attempt < 3 {
                                try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000) // 0.5s, 1s
                            }
                        }

                        // If summary still too short after retries, keep existing entry
                        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedSummary.isEmpty || trimmedSummary.count < minSummaryLength {
                            if let existingEntry = existingEntry {
                                return (feed.id, existingEntry, nil, false)
                            }
                            return (feed.id, nil, nil, false)
                        }

                        let entry = SidebarHeroCardView.Entry(
                            source: feed,
                            title: article.title,
                            oneLine: summary,
                            link: article.link,
                            isNew: isNew,
                            pubDate: article.pubDate
                        )
                        return (feed.id, entry, article.link, true)
                    } else {
                        // No new summary needed - wait 1s then reveal
                        if hasAnyNewArticles {
                            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        }

                        let summary = await ArticleSummarizer.shared.fastHeroSummary(url: article.link, articleText: article.summary) ?? ""

                        if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // Preserve isNew status from existing entry (don't reset blue dot)
                            let preservedIsNew = existingEntry?.isNew ?? isNew
                            let entry = SidebarHeroCardView.Entry(
                                source: feed,
                                title: article.title,
                                oneLine: summary,
                                link: article.link,
                                isNew: preservedIsNew,
                                pubDate: article.pubDate
                            )
                            return (feed.id, entry, nil, false)
                        }
                        return (feed.id, nil, nil, false)
                    }
                }
            }

            // Process results as they complete
            for await (feedID, entry, gradientLink, needsGradient) in group {
                processedSourceIDs.insert(feedID)

                if let entry = entry {
                    entriesBySourceID[feedID] = entry
                }

                // Remove shimmer for this source
                loadingSummarySourceIDs.remove(feedID)

                // Show gradient reveal for new summaries
                if let link = gradientLink, needsGradient {
                    gradientRevealLinks.insert(link)
                }

                // Update UI after each source completes
                updateHeroEntriesFromMap(entriesBySourceID)
            }
        }

        // For sources where feed fetch failed entirely, keep existing entries (preserve isNew status)
        for (sourceID, existingEntry) in existingEntriesBySource {
            if !processedSourceIDs.contains(sourceID) && selectedIDs.contains(sourceID) {
                entriesBySourceID[sourceID] = existingEntry
                loadingSummarySourceIDs.remove(sourceID)
            }
        }

        // Final update
        updateHeroEntriesFromMap(entriesBySourceID)

        saveHeroEntriesToCache()
        isLoadingHero = false
        isInitialLoad = false
        loadingSummarySourceIDs.removeAll()

        // If a refresh was requested while loading, run again
        if pendingHeroRefresh {
            pendingHeroRefresh = false
            Task { await loadHeroEntries() }
        }
    }

    /// Helper to update heroEntries from a source ID -> entry map, sorted by date
    private func updateHeroEntriesFromMap(_ map: [UUID: SidebarHeroCardView.Entry]) {
        let sorted = map.values.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            heroEntries = sorted
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
                if isHeroSource(source) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                }
            }
            .contentShape(Rectangle())
        }
        .padding(.leading, 20)
        .contextMenu {
            Button {
                toggleHeroSource(source)
            } label: {
                Label(
                    isHeroSource(source) ? "Remove from Highlights" : "Add to Highlights",
                    systemImage: isHeroSource(source) ? "minus.circle" : "plus.circle"
                )
            }
            .disabled(!isHeroSource(source) && heroSourceIDs.count >= 3)
            Button {
                renameText = source.title
                renamingSource = source
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                store.assign(source, to: nil)
            } label: {
                Label("Remove from Folder", systemImage: "folder.badge.minus")
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

    @ViewBuilder private var sidebar: some View {
        ZStack(alignment: .top) {
            List {
                Section {
                    if showLatestView {
                        NavigationLink {
                            CurrentView(refreshID: refreshID)
                                .environmentObject(store)
                        } label: {
                            Label("Latest", systemImage: "sparkles.rectangle.stack")
                                .contentShape(Rectangle())
                        }
                    }

                    if showTodayView {
                        NavigationLink {
                            AllArticlesView(refreshID: refreshID)
                                .environmentObject(store)
                        } label: {
                            Label("Today", systemImage: "newspaper.fill")
                                .contentShape(Rectangle())
                        }
                    }

                    ForEach(store.folders) { folder in
                        folderRow(folder)
                    }
                    .onMove { indices, destination in
                        store.folders.move(fromOffsets: indices, toOffset: destination)
                    }
                }
                header: {
                    HStack(spacing: 8) {
                        Text("Folders")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(areFoldersCollapsed ? 0 : 90))
                            .animation(.snappy(duration: 0.2), value: areFoldersCollapsed)
                        Spacer()
                        Text("\(store.folders.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.25)) {
                            areFoldersCollapsed.toggle()
                        }
                    }
                }
                .animation(.snappy(duration: 0.25), value: areFoldersCollapsed)

                Section {
                    if !areSourcesCollapsed {
                        ForEach(store.feeds) { source in
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
                                    if isHeroSource(source) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                            .font(.subheadline)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .contextMenu {
                                Button {
                                    toggleHeroSource(source)
                                } label: {
                                    if isHeroSource(source) {
                                        Label("Remove from Highlights", systemImage: "star.slash")
                                    } else if heroSourceIDs.count < 3 {
                                        Label("Add to Highlights", systemImage: "star")
                                    } else {
                                        Label("Highlights Full (3 max)", systemImage: "star.slash")
                                    }
                                }
                                .disabled(!isHeroSource(source) && heroSourceIDs.count >= 3)

                                Button {
                                    Task { await store.refreshIcon(for: source) }
                                } label: {
                                    Label("Refresh Icon", systemImage: "arrow.triangle.2.circlepath")
                                }
                                Button {
                                    renameText = source.title
                                    renamingSource = source
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Menu {
                                    ForEach(store.folders) { folder in
                                        Button {
                                            store.assign(source, to: folder)
                                        } label: {
                                            let isCurrentFolder = source.folderID == folder.id
                                            Label(folder.name, systemImage: isCurrentFolder ? "checkmark" : "folder")
                                        }
                                    }
                                    if source.folderID != nil {
                                        Button {
                                            store.assign(source, to: nil)
                                        } label: {
                                            Label("Remove from Folder", systemImage: "folder.badge.minus")
                                        }
                                    }
                                } label: {
                                    Label("Move to Folder", systemImage: "folder.badge.plus")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    if let idx = store.feeds.firstIndex(where: { $0.id == source.id }) {
                                        store.feeds.remove(at: idx)
                                        if selectedSource?.id == source.id {
                                            selectedSource = store.feeds.first
                                        }
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions {
                                Button {
                                    movingSource = source
                                    showingMoveDialog = true
                                } label: {
                                    Label("Move", systemImage: "folder")
                                }
                                Button(role: .destructive) {
                                    if let idx = store.feeds.firstIndex(where: { $0.id == source.id }) {
                                        store.feeds.remove(at: idx)
                                        if selectedSource?.id == source.id {
                                            selectedSource = store.feeds.first
                                        }
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onMove { indices, destination in
                            store.feeds.move(fromOffsets: indices, toOffset: destination)
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text("Sources")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(areSourcesCollapsed ? 0 : 90))
                            .animation(.snappy(duration: 0.2), value: areSourcesCollapsed)
                        Spacer()
                        Text("\(store.feeds.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.25)) {
                            areSourcesCollapsed.toggle()
                        }
                    }
                }
                .animation(.snappy(duration: 0.25), value: areSourcesCollapsed)
            }
            .id(sidebarRefreshTrigger)
            .navigationTitle("TodayRSS")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                if !heroSourceIDs.isEmpty {
                    SidebarHeroCardView(
                        entries: heroEntries,
                        expectedCount: heroSourceIDs.count,
                        isUpdating: isLoadingHero,
                        isCollapsed: isHeroCollapsed,
                        loadingSourceIDs: loadingSummarySourceIDs,
                        gradientRevealLinks: gradientRevealLinks,
                        onTapLink: { url in
                            heroWebLink = WebLink(url: url)
                        },
                        onToggleCollapse: {
                            withAnimation(.snappy(duration: 0.25)) {
                                isHeroCollapsed.toggle()
                            }
                        },
                        onGradientComplete: { link in
                            gradientRevealLinks.remove(link)
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .animation(.snappy(duration: 0.25), value: isHeroCollapsed)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showingAddFolder = true } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
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
                            heroEntries.removeAll()
                            UserDefaults.standard.removeObject(forKey: heroCacheKey)
                            Task {
                                await ArticleSummarizer.shared.clearHeroSummaries()
                                await loadHeroEntries()
                            }
                        } label: {
                            Label("Clear Today Highlights", systemImage: "sun.horizon")
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
                ReaderSafariView(url: w.url).ignoresSafeArea()
            }
            .confirmationDialog("Move to Folder", isPresented: $showingMoveDialog, presenting: movingSource) { source in
                ForEach(store.folders) { folder in
                    let isCurrentFolder = source.folderID == folder.id
                    Button(isCurrentFolder ? "\(folder.name) ✓" : folder.name) {
                        store.assign(source, to: folder)
                    }
                }
                if source.folderID != nil {
                    Button("Remove from Folder", role: .destructive) {
                        store.assign(source, to: nil)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { source in
                Text("Choose a folder for \(source.title)")
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

            // Refresh progress overlay at bottom
            VStack {
                Spacer()
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
                }
            }
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDetents([.large])
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
            sidebar
        } detail: {
            detailView
        }
        .onAppear {
            selectedSource = store.feeds.first
            store.backfillIcons()
            loadHeroSourceIDsFromiCloud()
            loadHeroEntriesFromCache()
            isHeroCollapsed = heroCollapsedOnLaunch
            Task {
                await loadHeroEntries()
                // Fetch latest articles to show blue dots on sources/folders
                await refreshLatestArticlesForSidebar()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Refresh sidebar to update blue dot indicators when app becomes active
                sidebarRefreshTrigger = UUID()
                Task { await loadHeroEntries() }
            } else if phase == .background {
                // Mark all current hero entries as "seen" when app goes to background
                // This clears blue dots on next launch if no new articles
                markAllHeroEntriesAsSeen()
            }
        }
        .onChange(of: store.feeds) { _, _ in
            Task { await loadHeroEntries() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReturnToSourceList)) { _ in
            // Refresh sidebar to update blue dot indicators
            sidebarRefreshTrigger = UUID()
            Task { await loadHeroEntries() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .backgroundSyncCompleted)) { _ in
            // Refresh hero entries and sidebar after background sync completes
            sidebarRefreshTrigger = UUID()
            Task { await loadHeroEntries() }
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let didReturnToSourceList = Notification.Name("didReturnToSourceList")
    static let backgroundSyncCompleted = Notification.Name("backgroundSyncCompleted")
}
