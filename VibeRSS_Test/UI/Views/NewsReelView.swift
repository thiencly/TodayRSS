//
//  NewsReelView.swift
//  VibeRSS_Test
//
//  TikTok-style news reel main container view using native ScrollView and TabView paging
//

import SwiftUI

struct NewsReelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: FeedStore
    @StateObject private var viewModel = NewsReelViewModel()

    // Sharing
    @State private var shareItem: URL?
    @State private var showingShareSheet: Bool = false

    // Reader mode
    @State private var webLink: WebLink?

    @State private var isRefreshing: Bool = false

    // Track current source for horizontal TabView paging
    @State private var selectedSourceIndex: Int = 0

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    // Background
                    Color.black.ignoresSafeArea()

                    // Main content
                    if viewModel.isLoading && viewModel.sources.isEmpty {
                        loadingView
                    } else if viewModel.sources.isEmpty {
                        emptyView
                    } else {
                        // Horizontal TabView for source switching
                        TabView(selection: $selectedSourceIndex) {
                            ForEach(Array(viewModel.sources.enumerated()), id: \.element.id) { index, source in
                                SourcePageView(
                                    viewModel: viewModel,
                                    sourceIndex: index,
                                    onArticleTap: { article in openInReader(article) },
                                    onSummaryRetry: { article in
                                        Task { await viewModel.retryReelSummary(for: article) }
                                    }
                                )
                                .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .ignoresSafeArea()
                    }
                }
            }
            .ignoresSafeArea()
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        HapticManager.shared.click()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .principal) {
                    if !viewModel.articles(forSourceAt: selectedSourceIndex).isEmpty {
                        GlassEffectContainer {
                            Text("\(viewModel.currentArticleIndex + 1)/\(viewModel.articles(forSourceAt: selectedSourceIndex).count)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .onTapGesture {
                            HapticManager.shared.click()
                            viewModel.currentArticleIndex = 0
                        }
                    }
                }
            }
        }
        .overlay(alignment: .trailing) {
            // Vertical action buttons on the right side
            if let article = viewModel.currentArticle {
                GlassEffectContainer {
                    VStack(spacing: 0) {
                        Button {
                            HapticManager.shared.click()
                            SavedArticlesManager.shared.toggleSaved(article: article)
                        } label: {
                            Image(systemName: SavedArticlesManager.shared.isSaved(url: article.link) ? "heart.fill" : "heart")
                                .font(.title2)
                                .foregroundStyle(SavedArticlesManager.shared.isSaved(url: article.link) ? .red : .white)
                                .frame(width: 44, height: 44)
                        }

                        Button {
                            HapticManager.shared.click()
                            refreshArticles()
                        } label: {
                            Group {
                                if isRefreshing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 44, height: 44)
                        }
                        .disabled(isRefreshing)

                        Button {
                            HapticManager.shared.click()
                            shareArticle(article)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .padding(.trailing, 16)
            }
        }
        .overlay(alignment: .top) {
            // Folder indicator pills below toolbar
            if viewModel.sources.count > 1 {
                FolderIndicatorView(
                    sources: viewModel.sources,
                    selectedIndex: $selectedSourceIndex,
                    onSelect: { newIndex in
                        HapticManager.shared.click()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedSourceIndex = newIndex
                        }
                    }
                )
                .padding(.top, 52)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.initialize(folders: store.folders, feeds: store.feeds)
        }
        .onChange(of: selectedSourceIndex) { _, newIndex in
            viewModel.selectSource(at: newIndex)
            Task {
                await viewModel.preloadAdjacentSources()
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await viewModel.preloadAdjacentSources()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareItem {
                ShareSheet(items: [url])
            }
        }
        .sheet(item: $webLink) { w in
            ArticleReaderView(url: w.url, articleTitle: w.title, articleDate: w.date, thumbnailURL: w.thumbnailURL, sourceIconURL: w.sourceIconURL, sourceTitle: w.sourceTitle)
        }
    }

    // MARK: - Actions

    private func openInReader(_ article: Article) {
        webLink = WebLink(url: article.link, title: article.title, date: article.pubDate, thumbnailURL: article.thumbnailURL, sourceIconURL: article.sourceIconURL, sourceTitle: article.sourceTitle)
    }

    private func shareArticle(_ article: Article) {
        shareItem = article.link
        showingShareSheet = true
    }

    private func refreshArticles() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await viewModel.refresh()
            await MainActor.run {
                isRefreshing = false
            }
        }
    }

    // MARK: - Loading & Empty States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            Text("Loading articles...")
                .font(.roundedHeadline)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "newspaper")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.5))

            Text("No Articles")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)

            Text("Add some feeds to see articles here")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))

            Button {
                HapticManager.shared.click()
                dismiss()
            } label: {
                GlassEffectContainer {
                    Text("Go Back")
                        .font(.roundedHeadline)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .glassEffect(.regular.interactive())
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }
}

// MARK: - Source Page View (Vertical Article Paging)

struct SourcePageView: View {
    @ObservedObject var viewModel: NewsReelViewModel
    let sourceIndex: Int
    let onArticleTap: (Article) -> Void
    let onSummaryRetry: (Article) -> Void

    @State private var scrolledArticleID: UUID?

    private var articles: [Article] {
        viewModel.articles(forSourceAt: sourceIndex)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(articles) { article in
                    NewsReelCardView(
                        article: article,
                        reelSummary: viewModel.reelSummary(for: article),
                        isLoadingSummary: viewModel.isSummaryLoading(for: article),
                        isRetryingSummary: viewModel.isSummaryRetrying(for: article),
                        hasSummaryFailed: viewModel.hasSummaryFailed(for: article),
                        onTitleTap: { onArticleTap(article) },
                        onRetryTap: { onSummaryRetry(article) }
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(article.id)
                    .onTapGesture {
                        HapticManager.shared.click()
                        onArticleTap(article)
                    }
                    .onAppear {
                        Task {
                            await viewModel.generateReelSummary(for: article)
                        }
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledArticleID)
        .onChange(of: scrolledArticleID) { _, newID in
            if sourceIndex == viewModel.currentSourceIndex,
               let newID = newID,
               let index = articles.firstIndex(where: { $0.id == newID }) {
                viewModel.currentArticleIndex = index
            }
        }
        .onAppear {
            // Set initial scroll position
            if let firstArticle = articles.first {
                scrolledArticleID = firstArticle.id
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
