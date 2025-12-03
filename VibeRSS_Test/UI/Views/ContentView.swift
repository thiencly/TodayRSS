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

private struct Shimmer: ViewModifier {
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

private extension View {
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
        let id = UUID()
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
    var onTapLink: ((URL) -> Void)? = nil
    var onToggleCollapse: (() -> Void)? = nil

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
            }
            .animation(.snappy(duration: 0.25), value: isCollapsed)
            .animation(.snappy(duration: 0.25), value: entries.count)
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
            Text(entry.oneLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? entry.title : entry.oneLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
    @State private var showingSettings: Bool = false

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("heroCollapsedOnLaunch") private var heroCollapsedOnLaunch: Bool = false

    @State private var heroEntries: [SidebarHeroCardView.Entry] = []
    @State private var isLoadingHero: Bool = false
    @State private var heroCardHeight: CGFloat = 200
    @State private var isHeroCollapsed: Bool = false
    @AppStorage("heroSourceIDs") private var heroSourceIDsData: Data = Data()
    private let heroCacheKey = "viberss.heroEntries"

    private var heroSourceIDs: Set<UUID> {
        (try? JSONDecoder().decode(Set<UUID>.self, from: heroSourceIDsData)) ?? []
    }

    private func saveHeroSourceIDs(_ ids: Set<UUID>) {
        heroSourceIDsData = (try? JSONEncoder().encode(ids)) ?? Data()
    }

    private func toggleHeroSource(_ source: Source) {
        var ids = heroSourceIDs
        if ids.contains(source.id) {
            ids.remove(source.id)
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
                // Reload widget timelines to pick up new thumbnails
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    private func downloadThumbnailsForWidget(articlesByFeed: [UUID: [FeedItem]]) async {
        var thumbnailURLs: [URL] = []
        var faviconURLs: Set<URL> = []

        for (_, articles) in articlesByFeed {
            for article in articles.prefix(5) {
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
            } catch {}
        }
    }

    private func loadHeroEntriesFromCache() {
        // Decode JSON off main thread to prevent UI freeze
        Task.detached(priority: .userInitiated) {
            guard let data = UserDefaults.standard.data(forKey: self.heroCacheKey) else { return }
            guard let decoded = try? JSONDecoder().decode([SidebarHeroCardView.Entry].self, from: data) else { return }
            // Filter out entries with empty summaries - they'll be regenerated
            let filtered = decoded.filter { !$0.oneLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            await MainActor.run {
                self.heroEntries = filtered
            }
        }
    }

    @MainActor private func loadHeroEntries() async {
        guard !isLoadingHero else { return }
        isLoadingHero = true

        let selectedIDs = heroSourceIDs
        let feeds = store.feeds.filter { selectedIDs.contains($0.id) }
        let previouslySeenLinks: Set<URL> = Set(heroEntries.map { $0.link })

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

        // Step 2: Process summaries one by one, most recent first
        var builtEntries: [SidebarHeroCardView.Entry] = []
        var processedSourceIDs: Set<UUID> = []
        var hasNewContent = false

        for (feed, article) in feedArticles {
            processedSourceIDs.insert(feed.id)
            let isNew = !previouslySeenLinks.contains(article.link)
            if isNew { hasNewContent = true }

            // Use fast hero summary - pass RSS description to avoid network fetch
            let summary = await ArticleSummarizer.shared.fastHeroSummary(url: article.link, articleText: article.summary) ?? ""

            // If summary generation failed, try to keep existing entry for this source
            if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let existingEntry = existingEntriesBySource[feed.id] {
                    // Update isNew flag on existing entry (it's now been "seen")
                    var updatedEntry = existingEntry
                    updatedEntry.isNew = false
                    builtEntries.append(updatedEntry)
                }
                continue
            }

            let entry = SidebarHeroCardView.Entry(
                source: feed,
                title: article.title,
                oneLine: summary,
                link: article.link,
                isNew: isNew,
                pubDate: article.pubDate
            )
            builtEntries.append(entry)

            // Only update UI progressively if there's actually new content
            if hasNewContent {
                heroEntries = builtEntries
            }
        }

        // For sources where feed fetch failed entirely, keep existing entries (mark as seen)
        for (sourceID, existingEntry) in existingEntriesBySource {
            if !processedSourceIDs.contains(sourceID) && selectedIDs.contains(sourceID) {
                var updatedEntry = existingEntry
                updatedEntry.isNew = false
                builtEntries.append(updatedEntry)
            }
        }

        // Final sort by date
        builtEntries.sort { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }

        // Check if content actually changed (compare links and isNew flags)
        let oldLinks = heroEntries.map { $0.link }
        let newLinks = builtEntries.map { $0.link }
        let oldIsNew = heroEntries.map { $0.isNew }
        let newIsNew = builtEntries.map { $0.isNew }

        let linksChanged = oldLinks != newLinks
        let isNewChanged = oldIsNew != newIsNew

        if linksChanged || isNewChanged || heroEntries.count != builtEntries.count {
            // If only isNew changed (no new articles), update without animation
            if !linksChanged && isNewChanged {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    heroEntries = builtEntries
                }
            } else {
                heroEntries = builtEntries
            }
        }

        saveHeroEntriesToCache()
        isLoadingHero = false
    }

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        let folderFeeds = store.feeds.filter { $0.folderID == folder.id }

        NavigationLink {
            FolderDetailView(folder: folder, refreshID: refreshID)
                .environmentObject(store)
        } label: {
            HStack {
                Label(folder.name, systemImage: "folder")
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
        NavigationLink {
            FeedDetailView(source: source, refreshID: refreshID)
        } label: {
            HStack(spacing: 12) {
                FeedIconView(iconURL: source.iconURL)
                Text(source.title)
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
                    isHeroSource(source) ? "Remove from Today" : "Add to Today",
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
                    NavigationLink {
                        CurrentView(refreshID: refreshID)
                            .environmentObject(store)
                    } label: {
                        Label("Current", systemImage: "sparkles.rectangle.stack")
                            .contentShape(Rectangle())
                    }

                    NavigationLink {
                        AllArticlesView(refreshID: refreshID)
                            .environmentObject(store)
                    } label: {
                        Label("All Articles", systemImage: "newspaper.fill")
                            .contentShape(Rectangle())
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
                            NavigationLink {
                                FeedDetailView(source: source, refreshID: refreshID)
                            } label: {
                                HStack(spacing: 12) {
                                    FeedIconView(iconURL: source.iconURL)
                                    Text(source.title)
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
                                        Label("Remove from Hero Card", systemImage: "star.slash")
                                    } else if heroSourceIDs.count < 3 {
                                        Label("Add to Hero Card", systemImage: "star")
                                    } else {
                                        Label("Hero Card Full (3 max)", systemImage: "star.slash")
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
                                            Label(folder.name, systemImage: "folder")
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
            .navigationTitle("TodayRSS")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                if !heroSourceIDs.isEmpty {
                    SidebarHeroCardView(
                        entries: heroEntries,
                        expectedCount: heroSourceIDs.count,
                        isUpdating: isLoadingHero,
                        isCollapsed: isHeroCollapsed,
                        onTapLink: { url in
                            heroWebLink = WebLink(url: url)
                        },
                        onToggleCollapse: {
                            withAnimation(.snappy(duration: 0.25)) {
                                isHeroCollapsed.toggle()
                            }
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .animation(.snappy(duration: 0.25), value: isHeroCollapsed)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingAddFolder = true } label: { Image(systemName: "folder.badge.plus") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
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
                        } label: {
                            Label("Refresh All Feeds", systemImage: "arrow.clockwise")
                        }
                        .disabled(isRefreshingAll)

                        Divider()

                        Button("Clear Hero Summaries") {
                            heroEntries.removeAll()
                            UserDefaults.standard.removeObject(forKey: heroCacheKey)
                            Task {
                                await ArticleSummarizer.shared.clearHeroSummaries()
                                await loadHeroEntries()
                            }
                        }
                        Button("Clear All Summaries", role: .destructive) {
                            Task { await ArticleSummarizer.shared.clearArticleSummaries() }
                        }
                    } label: {
                        if isRefreshingAll {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        }
                    }
                    .help("Refresh & Cache Tools")
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
                    Button(folder.name) {
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

            // Settings button at bottom left
            VStack {
                Spacer()
                HStack {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle().strokeBorder(Color.secondary.opacity(0.2))
                            )
                    }
                    .padding(.leading, 16)
                    .padding(.bottom, 16)
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDetents([.large])
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
            loadHeroEntriesFromCache()
            isHeroCollapsed = heroCollapsedOnLaunch
            Task { await loadHeroEntries() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await loadHeroEntries() }
            }
        }
        .onChange(of: store.feeds) { _, _ in
            Task { await loadHeroEntries() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReturnToSourceList)) { _ in
            Task { await loadHeroEntries() }
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let didReturnToSourceList = Notification.Name("didReturnToSourceList")
}
