import SwiftUI

struct CurrentView: View {
    @EnvironmentObject private var store: FeedStore
    var refreshID: UUID = UUID()

    @State private var items: [Article] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    @State private var webLink: WebLink?
    @State private var summarizingID: UUID?
    @State private var inlineSummaries: [UUID: String] = [:]
    @State private var expandedSummaries: Set<UUID> = []
    @State private var summaryErrors: Set<UUID> = []
    @State private var newArticleIDs: Set<UUID> = []
    @State private var previousArticleIDs: Set<UUID> = []

    @State private var aiSummarized: Set<UUID> = []
    @State private var currentDay: Date? = nil
    @State private var suppressNextRowTap = false
    @State private var hasCachedSummaryCache: Set<UUID> = []
    @State private var readURLs: Set<URL> = []
    @State private var seenURLs: Set<URL> = []
    @AppStorage("appTint") private var appTint: String = AppTint.default.rawValue

    private let service = FeedService()

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView().controlSize(.large)
            } else if let errorMessage, items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(errorMessage).multilineTextAlignment(.center)
                    Button("Retry") { Task { await loadLatestPerSource() } }
                }.padding()
            } else {
                List(items) { item in
                    let rowState = makeRowState(for: item)
                    ArticleRowView(
                        state: rowState,
                        onTapArticle: {
                            readURLs.insert(item.link)
                            Task { await ArticleReadStateManager.shared.markAsRead(item.link) }
                            webLink = WebLink(url: item.link, title: item.title, date: item.pubDate, thumbnailURL: item.thumbnailURL, sourceIconURL: item.sourceIconURL, sourceTitle: item.sourceTitle)
                        },
                        onTapSummarize: {
                            handleSummarizeAction(for: item)
                        },
                        onSave: {
                            SavedArticlesManager.shared.toggleSaved(article: item)
                        },
                        tintColor: AppTint(rawValue: appTint)?.color ?? .blue
                    )
                    .equatable()
                    .background(DayAnchorReporter(date: item.pubDate, coordinateSpaceName: "CurrentListScroll"))
                    .id(item.id)
                }
                .listStyle(.plain)
                .refreshable { await loadLatestPerSource() }
                .coordinateSpace(name: "CurrentListScroll")
                .onChange(of: items.count) { _, _ in preloadSummaries(for: items) }
                .task { preloadSummaries(for: items) }
                .onPreferenceChange(DayAnchorsKey.self) { anchors in
                    guard !anchors.isEmpty else { currentDay = nil; return }
                    let sorted = anchors.sorted { a, b in
                        let aScore = (a.minY >= 0) ? a.minY : (100000 + abs(a.minY))
                        let bScore = (b.minY >= 0) ? b.minY : (100000 + abs(b.minY))
                        return aScore < bScore
                    }
                    let topDay = sorted.first?.dayStart
                    if currentDay != topDay {
                        withAnimation(.easeInOut(duration: 0.15)) { currentDay = topDay }
                    }
                }
            }
        }
        .task(id: refreshID) { await loadLatestPerSource() }
        .onAppear {
            // Notify ContentView that user navigated to article list
            NotificationCenter.default.post(name: .didNavigateToArticleList, object: nil)
            // Load initial read/seen state
            Task {
                let urls = items.map { $0.link }
                let states = await ArticleReadStateManager.shared.getStates(for: urls)
                for state in states {
                    if !state.isNew { seenURLs.insert(state.url) }
                    if state.isRead { readURLs.insert(state.url) }
                }
            }
        }
        .onChange(of: items) { _, newItems in
            // Load read/seen state for new items
            Task {
                let urls = newItems.map { $0.link }
                let states = await ArticleReadStateManager.shared.getStates(for: urls)
                for state in states {
                    if !state.isNew { seenURLs.insert(state.url) }
                    if state.isRead { readURLs.insert(state.url) }
                }
                // Mark all articles as seen immediately (persists even if app is killed)
                // Local seenURLs is NOT updated so dots remain visible during this session
                await ArticleReadStateManager.shared.markAllAsSeen(urls)
            }
        }
        .navigationTitle("Latest")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $webLink) { w in
            ArticleReaderView(url: w.url, articleTitle: w.title, articleDate: w.date, thumbnailURL: w.thumbnailURL, sourceIconURL: w.sourceIconURL, sourceTitle: w.sourceTitle)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await loadLatestPerSource() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
            }
        }
        .onDisappear {
            // Mark all articles as seen first, then notify sidebar to refresh
            let urls = items.map { $0.link }
            Task {
                await ArticleReadStateManager.shared.markAllAsSeen(urls)
                NotificationCenter.default.post(name: .didReturnToSourceList, object: nil)
            }
        }
    }

    private func loadLatestPerSource() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        let feeds = store.feeds
        var collected: [Article] = []
        var articlesByFeed: [UUID: [FeedItem]] = [:]
        let service = self.service

        await withTaskGroup(of: (UUID, [FeedItem], Article?).self) { group in
            for src in feeds {
                group.addTask {
                    do {
                        var items = try await service.loadItems(from: src.url)
                        for i in items.indices {
                            items[i].sourceID = src.id
                            items[i].sourceTitle = src.title
                            items[i].sourceIconURL = src.iconURL
                        }
                        let latest = items.sorted(by: { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }).first
                        return (src.id, items, latest)
                    } catch {
                        return (src.id, [], nil)
                    }
                }
            }
            for await (feedID, allItems, latest) in group {
                if let a = latest { collected.append(a) }
                if !allItems.isEmpty {
                    articlesByFeed[feedID] = allItems
                }
            }
        }

        // Track latest articles for new indicator in sidebar
        if !articlesByFeed.isEmpty {
            for (feedID, articles) in articlesByFeed {
                let urls = articles.map { $0.link }
                Task { await ArticleReadStateManager.shared.updateLatestArticles(for: feedID, urls: urls) }
            }
        }

        collected.sort { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        await MainActor.run {
            let currentIDs = Set(collected.map { $0.id })
            if previousArticleIDs.isEmpty {
                newArticleIDs = []
            } else {
                newArticleIDs = currentIDs.subtracting(previousArticleIDs)
            }
            previousArticleIDs = currentIDs
            self.items = collected
            self.isLoading = false
        }
    }

    // MARK: - Row State Factory

    private func makeRowState(for item: Article) -> ArticleRowState {
        let aiSummary = inlineSummaries[item.id]
        let hasCached = (aiSummary != nil) || hasCachedSummaryCache.contains(item.id)
        let isNew = !seenURLs.contains(item.link)
        let isRead = readURLs.contains(item.link)

        return ArticleRowState(
            id: item.id,
            title: item.title,
            link: item.link,
            pubDate: item.pubDate,
            thumbnailURL: item.thumbnailURL,
            sourceIconURL: item.sourceIconURL,
            sourceTitle: item.sourceTitle ?? "Source",
            isNew: isNew,
            isRead: isRead,
            hasSummary: hasCached,
            summaryText: aiSummary,
            isExpanded: expandedSummaries.contains(item.id),
            isError: summaryErrors.contains(item.id),
            isGenerating: summarizingID == item.id,
            isSaved: SavedArticlesManager.shared.isSaved(url: item.link)
        )
    }

    private func handleSummarizeAction(for item: Article) {
        suppressNextRowTap = true
        let aiSummary = inlineSummaries[item.id]
        let hasSummary = (aiSummary != nil)

        if hasSummary {
            let length: ArticleSummarizer.Length = .short
            if expandedSummaries.contains(item.id) {
                // No animation for collapse to avoid List jumping
                expandedSummaries.remove(item.id)
                Task { await ArticleSummarizer.shared.setExpanded(false, url: item.link, length: length) }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSummaries.insert(item.id)
                }
                Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
            }
        } else if summarizingID != item.id {
            Task { await summarize(item) }
        }
    }

    private func preloadSummaries(for items: [Article]) {
        let length: ArticleSummarizer.Length = .short
        Task { @MainActor in
            var updated = inlineSummaries
            var expanded = expandedSummaries
            var cachedStatus = hasCachedSummaryCache

            for item in items {
                if ArticleSummarizer.hasCachedSummary(url: item.link, length: length) {
                    cachedStatus.insert(item.id)
                }

                if updated[item.id] == nil, let cached = await ArticleSummarizer.shared.cachedSummary(for: item.link, length: length) {
                    updated[item.id] = cached
                    cachedStatus.insert(item.id)
                }
                if await ArticleSummarizer.shared.isExpanded(url: item.link, length: length) {
                    expanded.insert(item.id)
                } else {
                    expanded.remove(item.id)
                }
            }
            inlineSummaries = updated
            expandedSummaries = expanded
            hasCachedSummaryCache = cachedStatus
        }
    }

    @MainActor private func summarize(_ item: Article) async {
        summaryErrors.remove(item.id)
        summarizingID = item.id
        let length: ArticleSummarizer.Length = .short
        if !expandedSummaries.contains(item.id) {
            withAnimation(.easeInOut(duration: 0.2)) { expandedSummaries.insert(item.id) }
            Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
        }

        // Retry logic for when on-device AI becomes temporarily unavailable
        let maxRetries = 2
        var attempt = 0
        var sawAny = false
        var latestText = ""

        while attempt < maxRetries && !sawAny {
            if attempt > 0 {
                // Wait before retry - gives the on-device model time to recover
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
            }

            var lastUpdateTime = Date.distantPast
            let throttleInterval: TimeInterval = 0.05  // 50ms = 20hz

            let stream = await ArticleSummarizer.shared.streamSummary(url: item.link, length: length, seedText: item.summary)
            for await partial in stream {
                sawAny = true
                latestText = partial
                let now = Date()
                if now.timeIntervalSince(lastUpdateTime) >= throttleInterval {
                    lastUpdateTime = now
                    inlineSummaries[item.id] = latestText
                    summaryErrors.remove(item.id)
                    aiSummarized.insert(item.id)
                }
            }

            attempt += 1
        }

        // Final update
        if sawAny {
            inlineSummaries[item.id] = latestText
            summaryErrors.remove(item.id)
            aiSummarized.insert(item.id)
        } else {
            summaryErrors.insert(item.id)
        }
        summarizingID = nil
    }
}
