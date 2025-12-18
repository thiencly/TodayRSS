import SwiftUI

struct FolderDetailView: View {
    let folder: Folder
    var refreshID: UUID = UUID()
    @EnvironmentObject private var store: FeedStore
    @StateObject private var vm = FolderItemsViewModel()
    @State private var webLink: WebLink?
    @State private var summarizingID: UUID?
    @State private var inlineSummaries: [UUID: String] = [:]
    @State private var expandedSummaries: Set<UUID> = []
    @State private var summaryErrors: Set<UUID> = []

    @State private var aiSummarized: Set<UUID> = []
    @State private var currentDay: Date? = nil
    @State private var suppressNextRowTap = false
    @State private var hasCachedSummaryCache: Set<UUID> = []
    @State private var readURLs: Set<URL> = []
    @State private var seenURLs: Set<URL> = []

    var body: some View {
        Group {
            if vm.isLoading && vm.items.isEmpty {
                ProgressView().controlSize(.large)
            } else if let error = vm.errorMessage, vm.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).multilineTextAlignment(.center)
                    Button("Retry") { Task { await vm.load(for: folder, feeds: store.feeds) } }
                }.padding()
            } else {
                List(vm.items) { item in
                    let rowState = makeRowState(for: item)
                    ArticleRowView(
                        state: rowState,
                        onTapArticle: {
                            readURLs.insert(item.link)
                            Task { await ArticleReadStateManager.shared.markAsRead(item.link) }
                            webLink = WebLink(url: item.link, date: item.pubDate)
                        },
                        onTapSummarize: {
                            handleSummarizeAction(for: item)
                        }
                    )
                    .equatable()
                    .background(DayAnchorReporter(date: item.pubDate, coordinateSpaceName: "FolderListScroll"))
                    .id(item.id)
                }
                .listStyle(.plain)
                .refreshable { await vm.load(for: folder, feeds: store.feeds) }
                .coordinateSpace(name: "FolderListScroll")
                .onChange(of: vm.items.count) { _, _ in preloadSummaries(for: vm.items) }
                .task { preloadSummaries(for: vm.items) }
                .onPreferenceChange(DayAnchorsKey.self) { anchors in
                    guard !anchors.isEmpty else {
                        currentDay = nil
                        return
                    }
                    let sorted = anchors.sorted { a, b in
                        let aScore = (a.minY >= 0) ? a.minY : (100000 + abs(a.minY))
                        let bScore = (b.minY >= 0) ? b.minY : (100000 + abs(b.minY))
                        return aScore < bScore
                    }
                    let topDay = sorted.first?.dayStart
                    if currentDay != topDay {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            currentDay = topDay
                        }
                    }
                }
                .safeAreaInset(edge: .top) {
                    if let d = currentDay {
                        HStack {
                            FloatingDayChip(date: d)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 0)
                        .padding(.leading, 16)
                        .padding(.trailing, 16)
                        .padding(.bottom, 6)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .task(id: refreshID) { await vm.load(for: folder, feeds: store.feeds) }
        .onAppear {
            // Notify ContentView that user navigated to article list
            NotificationCenter.default.post(name: .didNavigateToArticleList, object: nil)
            // Load initial read/seen state
            Task {
                let urls = vm.items.map { $0.link }
                let states = await ArticleReadStateManager.shared.getStates(for: urls)
                for state in states {
                    if !state.isNew { seenURLs.insert(state.url) }
                    if state.isRead { readURLs.insert(state.url) }
                }
            }
        }
        .onChange(of: vm.items) { _, newItems in
            // Load read/seen state for new items
            Task {
                let urls = newItems.map { $0.link }
                let states = await ArticleReadStateManager.shared.getStates(for: urls)
                for state in states {
                    if !state.isNew { seenURLs.insert(state.url) }
                    if state.isRead { readURLs.insert(state.url) }
                }
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $webLink) { w in
            ArticleReaderView(url: w.url, articleTitle: nil, articleDate: w.date)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await vm.load(for: folder, feeds: store.feeds) }
                } label: {
                    if vm.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(vm.isLoading)
            }
        }
        .onDisappear {
            // Mark all articles as seen first, then notify sidebar to refresh
            let urls = vm.items.map { $0.link }
            Task {
                await ArticleReadStateManager.shared.markAllAsSeen(urls)
                NotificationCenter.default.post(name: .didReturnToSourceList, object: nil)
            }
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
            isGenerating: summarizingID == item.id
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
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedSummaries.insert(item.id)
            }
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
        if !sawAny {
            summaryErrors.insert(item.id)
        }
        summarizingID = nil
    }
}
