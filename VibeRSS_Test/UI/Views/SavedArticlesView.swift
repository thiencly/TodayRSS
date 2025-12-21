import SwiftUI

struct SavedArticlesView: View {
    @State private var savedManager = SavedArticlesManager.shared
    @State private var webLink: WebLink?
    @State private var summarizingID: UUID?
    @State private var inlineSummaries: [UUID: String] = [:]
    @State private var expandedSummaries: Set<UUID> = []
    @State private var summaryErrors: Set<UUID> = []
    @State private var hasCachedSummaryCache: Set<UUID> = []
    @State private var readURLs: Set<URL> = []
    @AppStorage("appTint") private var appTint: String = AppTint.default.rawValue

    var body: some View {
        Group {
            if savedManager.savedArticles.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(savedManager.savedArticles) { article in
                        let rowState = makeRowState(for: article)
                        ArticleRowView(
                            state: rowState,
                            onTapArticle: {
                                readURLs.insert(article.url)
                                Task { await ArticleReadStateManager.shared.markAsRead(article.url) }
                                webLink = WebLink(url: article.url, title: article.title, date: article.pubDate, thumbnailURL: article.thumbnailURL, sourceIconURL: article.sourceIconURL, sourceTitle: article.sourceTitle)
                            },
                            onTapSummarize: {
                                handleSummarizeAction(for: article)
                            },
                            onSave: {
                                withAnimation {
                                    savedManager.unsave(url: article.url)
                                }
                            },
                            tintColor: AppTint(rawValue: appTint)?.color ?? .blue
                        )
                        .equatable()
                        .id(article.id)
                    }
                    .onDelete(perform: deleteArticles)
                }
                .listStyle(.plain)
                .onChange(of: savedManager.savedArticles.count) { _, _ in preloadSummaries() }
                .task { preloadSummaries() }
            }
        }
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $webLink) { w in
            ArticleReaderView(url: w.url, articleTitle: w.title, articleDate: w.date, thumbnailURL: w.thumbnailURL, sourceIconURL: w.sourceIconURL, sourceTitle: w.sourceTitle)
        }
        .onAppear {
            Task {
                let urls = savedManager.savedArticles.map { $0.url }
                let states = await ArticleReadStateManager.shared.getStates(for: urls)
                for state in states {
                    if state.isRead { readURLs.insert(state.url) }
                }
            }
        }
    }

    // MARK: - Row State Factory

    private func makeRowState(for article: SavedArticle) -> ArticleRowState {
        let aiSummary = inlineSummaries[article.id]
        let hasCached = (aiSummary != nil) || hasCachedSummaryCache.contains(article.id)
        let isRead = readURLs.contains(article.url)

        return ArticleRowState(
            id: article.id,
            title: article.title,
            link: article.url,
            pubDate: article.pubDate,
            thumbnailURL: article.thumbnailURL,
            sourceIconURL: article.sourceIconURL,
            sourceTitle: article.sourceTitle ?? "Source",
            isNew: false,  // Saved articles are never "new"
            isRead: isRead,
            hasSummary: hasCached,
            summaryText: aiSummary,
            isExpanded: expandedSummaries.contains(article.id),
            isError: summaryErrors.contains(article.id),
            isGenerating: summarizingID == article.id,
            isSaved: true  // All articles in this view are saved
        )
    }

    // MARK: - Summary Handling

    private func handleSummarizeAction(for article: SavedArticle) {
        let aiSummary = inlineSummaries[article.id]
        let hasSummary = (aiSummary != nil)

        if hasSummary {
            let length: ArticleSummarizer.Length = .short
            if expandedSummaries.contains(article.id) {
                expandedSummaries.remove(article.id)
                Task { await ArticleSummarizer.shared.setExpanded(false, url: article.url, length: length) }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSummaries.insert(article.id)
                }
                Task { await ArticleSummarizer.shared.setExpanded(true, url: article.url, length: length) }
            }
        } else if summarizingID != article.id {
            Task { await summarize(article) }
        }
    }

    private func preloadSummaries() {
        let length: ArticleSummarizer.Length = .short
        Task { @MainActor in
            var updated = inlineSummaries
            var expanded = expandedSummaries
            var cachedStatus = hasCachedSummaryCache

            for article in savedManager.savedArticles {
                if ArticleSummarizer.hasCachedSummary(url: article.url, length: length) {
                    cachedStatus.insert(article.id)
                }

                if updated[article.id] == nil, let cached = await ArticleSummarizer.shared.cachedSummary(for: article.url, length: length) {
                    updated[article.id] = cached
                    cachedStatus.insert(article.id)
                }
                if await ArticleSummarizer.shared.isExpanded(url: article.url, length: length) {
                    expanded.insert(article.id)
                } else {
                    expanded.remove(article.id)
                }
            }
            inlineSummaries = updated
            expandedSummaries = expanded
            hasCachedSummaryCache = cachedStatus
        }
    }

    @MainActor private func summarize(_ article: SavedArticle) async {
        summaryErrors.remove(article.id)
        summarizingID = article.id
        let length: ArticleSummarizer.Length = .short

        if !expandedSummaries.contains(article.id) {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedSummaries.insert(article.id)
            }
            Task { await ArticleSummarizer.shared.setExpanded(true, url: article.url, length: length) }
        }

        var sawAny = false
        var lastUpdateTime = Date.distantPast
        var latestText = ""
        let throttleInterval: TimeInterval = 0.05

        let stream = await ArticleSummarizer.shared.streamSummary(url: article.url, length: length, seedText: nil)
        for await partial in stream {
            sawAny = true
            latestText = partial
            let now = Date()
            if now.timeIntervalSince(lastUpdateTime) >= throttleInterval {
                lastUpdateTime = now
                inlineSummaries[article.id] = latestText
                summaryErrors.remove(article.id)
            }
        }

        if sawAny {
            inlineSummaries[article.id] = latestText
            summaryErrors.remove(article.id)
        } else {
            summaryErrors.insert(article.id)
        }
        summarizingID = nil
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Saved Articles")
                .font(.roundedHeadline)

            Text("Tap the heart icon in the reader or news reel to save articles for later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Actions

    private func deleteArticles(at offsets: IndexSet) {
        for index in offsets {
            let article = savedManager.savedArticles[index]
            savedManager.unsave(url: article.url)
        }
    }
}
