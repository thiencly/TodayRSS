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

    @AppStorage("summaryLength") private var summaryLengthRaw: String = "short"
    @State private var aiSummarized: Set<UUID> = []
    @State private var currentDay: Date? = nil
    @State private var suppressNextRowTap = false

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
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline)
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(2)
                                .contentShape(Rectangle())
                                .onTapGesture { webLink = WebLink(url: item.link) }

                            Group {
                                let isError = summaryErrors.contains(item.id)
                                let aiSummary = inlineSummaries[item.id]

                                HStack(spacing: 6) {
                                    SummarizeButton(
                                        state: { () -> SummarizeButton.ButtonState in
                                            if summarizingID == item.id { return .generating }
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
                                            let hasCached = (aiSummary != nil) || ArticleSummarizer.hasCachedSummary(url: item.link, length: length)
                                            if hasCached { return .hasSummary(isExpanded: expandedSummaries.contains(item.id)) }
                                            return .none
                                        }()
                                    ) {
                                        suppressNextRowTap = true
                                        let hasSummary = (aiSummary != nil)
                                        if hasSummary {
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
                                            if expandedSummaries.contains(item.id) {
                                                withAnimation(.easeInOut(duration: 0.2)) { expandedSummaries.remove(item.id) }
                                                Task { await ArticleSummarizer.shared.setExpanded(false, url: item.link, length: length) }
                                            } else {
                                                withAnimation(.easeInOut(duration: 0.2)) { expandedSummaries.insert(item.id) }
                                                Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
                                            }
                                        } else if summarizingID != item.id {
                                            Task { await summarize(item) }
                                        }
                                    }
                                    .disabled(isError)

                                    if newArticleIDs.contains(item.id) {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 6, height: 6)
                                            .accessibilityLabel("New article")
                                    }
                                }

                                ZStack(alignment: .topLeading) {
                                    if let aiSummary {
                                        CollapsibleText(text: aiSummary, isExpanded: expandedSummaries.contains(item.id))
                                    } else if isError {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                            Text("Summarization unavailable on this device.")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.top, 4)

                            HStack(alignment: .center, spacing: 6) {
                                SourceBadge(iconURL: item.sourceIconURL, name: item.sourceTitle ?? "Source")
                                if let date = item.pubDate {
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(date, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        Spacer(minLength: 12)
                        if let thumb = item.thumbnailURL {
                            ArticleThumbnailView(url: thumb)
                                .contentShape(Rectangle())
                                .onTapGesture { webLink = WebLink(url: item.link) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DayAnchorReporter(date: item.pubDate, coordinateSpaceName: "CurrentListScroll"))
                    .id(item.id)
                    .transaction { $0.disablesAnimations = false }
                }
                .listStyle(.plain)
                .transaction { $0.animation = nil }
                .refreshable { await loadLatestPerSource() }
                .coordinateSpace(name: "CurrentListScroll")
                .task(id: items.map { $0.id }) { preloadSummaries(for: items) }
                .onChange(of: summaryLengthRaw) { _, _ in }
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
        .navigationTitle("Current")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $webLink) { w in
            ReaderSafariView(url: w.url).ignoresSafeArea()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("Summary Length") {
                        Button {
                            summaryLengthRaw = "short"
                        } label: {
                            HStack { Text("Short"); if summaryLengthRaw == "short" { Image(systemName: "checkmark") } }
                        }
                        Button {
                            summaryLengthRaw = "long"
                        } label: {
                            HStack { Text("Long"); if summaryLengthRaw == "long" { Image(systemName: "checkmark") } }
                        }
                    }
                    Button("Clear Summaries", role: .destructive) {
                        inlineSummaries.removeAll()
                        aiSummarized.removeAll()
                        expandedSummaries.removeAll()
                        summaryErrors.removeAll()
                        Task { await ArticleSummarizer.shared.clearCache() }
                    }
                    Button("Clear Article Text Cache", role: .destructive) {
                        Task { await ArticleTextCache.shared.clear() }
                    }
                } label: { Image(systemName: "sparkles") }
            }
        }
    }

    private func loadLatestPerSource() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        let feeds = store.feeds
        var collected: [Article] = []
        let service = self.service
        await withTaskGroup(of: Article?.self) { group in
            for src in feeds {
                group.addTask {
                    do {
                        var items = try await service.loadItems(from: src.url)
                        for i in items.indices {
                            items[i].sourceID = src.id
                            items[i].sourceTitle = src.title
                            items[i].sourceIconURL = src.iconURL
                        }
                        guard let latest = items.sorted(by: { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }).first else {
                            return nil
                        }
                        return latest
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                if let a = result { collected.append(a) }
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

    private func preloadSummaries(for items: [Article]) {
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
        Task { @MainActor in
            var updated = inlineSummaries
            var expanded = expandedSummaries
            for item in items {
                if updated[item.id] == nil, let cached = await ArticleSummarizer.shared.cachedSummary(for: item.link, length: length) {
                    updated[item.id] = cached
                }
                if await ArticleSummarizer.shared.isExpanded(url: item.link, length: length) {
                    expanded.insert(item.id)
                } else {
                    expanded.remove(item.id)
                }
            }
            inlineSummaries = updated
            expandedSummaries = expanded
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
