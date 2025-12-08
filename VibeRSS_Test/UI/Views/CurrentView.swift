import SwiftUI
import WidgetKit

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

    @AppStorage("summaryLength") private var summaryLengthRaw: String = "short"
    @State private var aiSummarized: Set<UUID> = []
    @State private var currentDay: Date? = nil
    @State private var suppressNextRowTap = false
    @State private var hasCachedSummaryCache: Set<UUID> = []
    @State private var showLengthChangeAlert: Bool = false
    @State private var pendingLengthChange: String? = nil

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
                            webLink = WebLink(url: item.link)
                        },
                        onTapSummarize: {
                            handleSummarizeAction(for: item)
                        }
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
        .overlay(alignment: .bottomTrailing) {
            if !items.isEmpty {
                FloatingRefreshButton(isLoading: isLoading) {
                    Task { await loadLatestPerSource() }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 24)
            }
        }
        .task(id: refreshID) { await loadLatestPerSource() }
        .navigationTitle("Latest")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $webLink) { w in
            ReaderSafariView(url: w.url).ignoresSafeArea()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("Summary Length") {
                        Button {
                            if summaryLengthRaw != "short" {
                                pendingLengthChange = "short"
                                showLengthChangeAlert = true
                            }
                        } label: {
                            HStack { Text("Short"); if summaryLengthRaw == "short" { Image(systemName: "checkmark") } }
                        }
                        Button {
                            if summaryLengthRaw != "long" {
                                pendingLengthChange = "long"
                                showLengthChangeAlert = true
                            }
                        } label: {
                            HStack { Text("Long"); if summaryLengthRaw == "long" { Image(systemName: "checkmark") } }
                        }
                    }
                    Button("Clear Summaries", role: .destructive) {
                        inlineSummaries.removeAll()
                        aiSummarized.removeAll()
                        expandedSummaries.removeAll()
                        summaryErrors.removeAll()
                        Task { await ArticleSummarizer.shared.clearArticleSummaries() }
                    }
                } label: { Image(systemName: "sparkles") }
            }
        }
        .onDisappear {
            NotificationCenter.default.post(name: .didReturnToSourceList, object: nil)
        }
        .alert("Change Summary Length?", isPresented: $showLengthChangeAlert) {
            Button("Cancel", role: .cancel) {
                pendingLengthChange = nil
            }
            Button("Continue", role: .destructive) {
                if let newLength = pendingLengthChange {
                    // Clear local state
                    inlineSummaries.removeAll()
                    aiSummarized.removeAll()
                    expandedSummaries.removeAll()
                    summaryErrors.removeAll()
                    hasCachedSummaryCache.removeAll()
                    // Clear cached summaries (not hero summaries)
                    Task { await ArticleSummarizer.shared.clearArticleSummaries() }
                    // Apply new length
                    summaryLengthRaw = newLength
                    pendingLengthChange = nil
                }
            }
        } message: {
            Text("Changing summary length will clear all existing article summaries. This won't affect Today Highlights.")
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

        // Sync to widgets
        if !articlesByFeed.isEmpty {
            WidgetUpdater.shared.syncFeedsToWidget(articlesByFeed: articlesByFeed)
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

        return ArticleRowState(
            id: item.id,
            title: item.title,
            link: item.link,
            pubDate: item.pubDate,
            thumbnailURL: item.thumbnailURL,
            sourceIconURL: item.sourceIconURL,
            sourceTitle: item.sourceTitle ?? "Source",
            isNew: newArticleIDs.contains(item.id),
            hasSummary: hasCached,
            summaryText: aiSummary,
            isExpanded: expandedSummaries.contains(item.id),
            isError: summaryErrors.contains(item.id),
            isGenerating: summarizingID == item.id
        )
    }

    private func handleSummarizeAction(for item: Article) {
        suppressNextRowTap = true
        let aiSummary = inlineSummaries[item.id]
        let hasSummary = (aiSummary != nil)

        if hasSummary {
            let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
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
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
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
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
        if !expandedSummaries.contains(item.id) {
            withAnimation(.easeInOut(duration: 0.2)) { expandedSummaries.insert(item.id) }
            Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
        }
        var sawAny = false
        let stream = await ArticleSummarizer.shared.streamSummary(url: item.link, length: length, seedText: item.summary)
        for await partial in stream {
            sawAny = true
            inlineSummaries[item.id] = partial
            summaryErrors.remove(item.id)
            aiSummarized.insert(item.id)
        }
        if !sawAny { summaryErrors.insert(item.id) }
        summarizingID = nil
    }
}
