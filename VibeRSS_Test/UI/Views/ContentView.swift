import SwiftUI

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
        let isNew: Bool
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
                        // Show shimmer placeholders for remaining entries still loading
                        if !isCollapsed && remainingPlaceholderCount > 0 {
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
            Text(entry.oneLine.isEmpty ? entry.title : entry.oneLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTapLink?(entry.link) }
        .redacted(reason: isUpdating ? .placeholder : [])
        .shimmer(if: isUpdating)
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

// MARK: - Content View

struct ContentView: View {
    @StateObject private var store = FeedStore()
    @State private var selectedSource: Source?
    @State private var showingAdd = false
    @State private var showingAddFolder = false
    @State private var movingSource: Source?
    @State private var showingMoveDialog = false
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
    @State private var areSourcesCollapsed: Bool = false
    @State private var areFoldersCollapsed: Bool = false
    @State private var showingSettings: Bool = false
    @Namespace private var settingsTransition

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
                            let items = try await refreshService.loadItems(from: feed.url)
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
        do {
            let data = try JSONEncoder().encode(heroEntries)
            UserDefaults.standard.set(data, forKey: heroCacheKey)
        } catch {}
    }

    private func loadHeroEntriesFromCache() {
        if let data = UserDefaults.standard.data(forKey: heroCacheKey) {
            if let decoded = try? JSONDecoder().decode([SidebarHeroCardView.Entry].self, from: data) {
                heroEntries = decoded
            }
        }
    }

    @MainActor private func loadHeroEntries() async {
        guard !isLoadingHero else { return }
        isLoadingHero = true

        let selectedIDs = heroSourceIDs
        let feeds = store.feeds.filter { selectedIDs.contains($0.id) }
        let previouslySeenLinks: Set<URL> = Set(heroEntries.map { $0.link })

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

        // Step 2: Process summaries one by one, most recent first, updating UI after each
        var builtEntries: [SidebarHeroCardView.Entry] = []

        for (index, (feed, article)) in feedArticles.enumerated() {
            let isNew = !previouslySeenLinks.contains(article.link)

            // Use fast hero summary - optimized for speed
            let summary = await ArticleSummarizer.shared.fastHeroSummary(url: article.link, articleText: nil) ?? ""

            let entry = SidebarHeroCardView.Entry(
                source: feed,
                title: article.title,
                oneLine: summary,
                link: article.link,
                isNew: isNew,
                pubDate: article.pubDate
            )
            builtEntries.append(entry)

            // Update UI after each entry is processed
            heroEntries = builtEntries

            // After first entry is ready, stop showing loading shimmer
            // so collapsed view shows content immediately
            if index == 0 {
                isLoadingHero = false
            }
        }

        saveHeroEntriesToCache()
        isLoadingHero = false
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

                    if !areFoldersCollapsed {
                        ForEach(store.folders) { folder in
                            NavigationLink {
                                FolderDetailView(folder: folder, refreshID: refreshID)
                                    .environmentObject(store)
                            } label: {
                                HStack {
                                    Label(folder.name, systemImage: "folder")
                                    Spacer()
                                    Text("\(store.feeds.filter { $0.folderID == folder.id }.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    store.removeFolder(folder)
                                }
                            }
                        }
                        .onMove { indices, destination in
                            store.folders.move(fromOffsets: indices, toOffset: destination)
                        }
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

                                Button("Refresh Icon") {
                                    Task { await store.refreshIcon(for: source) }
                                }
                                Menu("Move to Folder") {
                                    ForEach(store.folders) { folder in
                                        Button(folder.name) {
                                            store.assign(source, to: folder)
                                        }
                                    }
                                    if source.folderID != nil {
                                        Button("Remove from Folder") {
                                            store.assign(source, to: nil)
                                        }
                                    }
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    if let idx = store.feeds.firstIndex(where: { $0.id == source.id }) {
                                        store.feeds.remove(at: idx)
                                        if selectedSource?.id == source.id {
                                            selectedSource = store.feeds.first
                                        }
                                    }
                                }
                            }
                            .swipeActions {
                                Button("Move") {
                                    movingSource = source
                                    showingMoveDialog = true
                                }
                                Button("Delete", role: .destructive) {
                                    if let idx = store.feeds.firstIndex(where: { $0.id == source.id }) {
                                        store.feeds.remove(at: idx)
                                        if selectedSource?.id == source.id {
                                            selectedSource = store.feeds.first
                                        }
                                    }
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
                    .padding(.horizontal, 16)
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

                        Button("Clear Hero Cache") {
                            heroEntries.removeAll()
                            UserDefaults.standard.removeObject(forKey: heroCacheKey)
                            Task { await loadHeroEntries() }
                        }
                        Button("Clear All Summaries", role: .destructive) {
                            Task { await ArticleSummarizer.shared.clearCache() }
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
                .presentationDetents([.medium])
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
                    .matchedTransitionSource(id: "settings", in: settingsTransition)
                    .padding(.leading, 16)
                    .padding(.bottom, 16)
                    Spacer()
                }
            }
        }
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView()
                .navigationTransition(.zoom(sourceID: "settings", in: settingsTransition))
        }
    }

    @ViewBuilder private var detailView: some View {
        if let source = selectedSource ?? store.feeds.first {
            FeedDetailView(source: source, refreshID: refreshID)
        } else {
            ContentPlaceholder()
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationDestination(for: Source.self) { source in
            FeedDetailView(source: source, refreshID: refreshID)
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
    }
}
