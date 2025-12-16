//
//  NewsReelView.swift
//  VibeRSS_Test
//
//  TikTok-style news reel main container view
//

import SwiftUI

struct NewsReelView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FeedStore
    @StateObject private var viewModel = NewsReelViewModel()

    // Gesture and navigation state
    @State private var dragOffset: CGSize = .zero
    @State private var showingExpandedSummary: Bool = false
    @State private var expandedSummaryText: String = ""
    @State private var currentSummaryStream: AsyncStream<String>?

    // Sharing
    @State private var shareItem: URL?
    @State private var showingShareSheet: Bool = false

    // Reader mode
    @State private var webLink: WebLink?

    @State private var isGeneratingExpanded: Bool = false

    // Gesture thresholds
    private let swipeThreshold: CGFloat = 50
    private let velocityThreshold: CGFloat = 300

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    // Background
                    Color.black.ignoresSafeArea()

                    // Main content
                    if viewModel.isLoading && viewModel.currentArticles.isEmpty {
                        loadingView
                    } else if viewModel.currentArticles.isEmpty {
                        emptyView
                    } else {
                        articleCardsView(geometry: geometry)
                    }

                }
                .overlay(alignment: .top) {
                    // Folder indicator pills below toolbar
                    if viewModel.sources.count > 1 {
                        FolderIndicatorView(
                            sources: viewModel.sources,
                            selectedIndex: Binding(
                                get: { viewModel.currentSourceIndex },
                                set: { viewModel.selectSource(at: $0) }
                            )
                        )
                        .padding(.top, 4)
                    }
                }
            }
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
                    if !viewModel.currentArticles.isEmpty {
                        Text("\(viewModel.currentArticleIndex + 1)/\(viewModel.currentArticles.count)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.currentArticle != nil {
                        Button {
                            HapticManager.shared.click()
                            if let article = viewModel.currentArticle {
                                shareArticle(article)
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.initialize(folders: store.folders, feeds: store.feeds)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareItem {
                ShareSheet(items: [url])
            }
        }
        .fullScreenCover(item: $webLink) { w in
            ReaderSafariView(url: w.url).ignoresSafeArea()
        }
    }

    // MARK: - Article Cards

    @ViewBuilder
    private func articleCardsView(geometry: GeometryProxy) -> some View {
        let articles = viewModel.currentArticles
        let currentIndex = viewModel.currentArticleIndex

        ZStack {
            ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                if abs(index - currentIndex) <= 1 {
                    let isCurrentArticle = index == currentIndex
                    NewsReelCardView(
                        article: article,
                        reelSummary: viewModel.reelSummary(for: article),
                        isLoadingSummary: viewModel.isSummaryLoading(for: article),
                        isExpanded: isCurrentArticle && showingExpandedSummary,
                        expandedSummary: isCurrentArticle ? expandedSummaryText : "",
                        isStreamingSummary: isCurrentArticle && isGeneratingExpanded,
                        summaryLength: "long",
                        onTitleTap: { openInReader(article) },
                        onSummaryTap: { expandSummary(for: article) },
                        onCollapseTap: { collapseSummary() }
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .offset(y: cardOffset(for: index, currentIndex: currentIndex, geometry: geometry))
                    .opacity(cardOpacity(for: index, currentIndex: currentIndex))
                    .zIndex(index == currentIndex ? 1 : 0)
                    .onAppear {
                        // Generate summary when card appears
                        Task {
                            await viewModel.generateReelSummary(for: article)
                        }
                    }
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    handleDragEnd(value: value)
                }
        )
    }

    private func cardOffset(for index: Int, currentIndex: Int, geometry: GeometryProxy) -> CGFloat {
        let baseOffset = CGFloat(index - currentIndex) * geometry.size.height

        if index == currentIndex {
            // Current card follows drag
            return dragOffset.height
        } else if index == currentIndex + 1 && dragOffset.height < 0 {
            // Next card peeks up as we swipe up
            return baseOffset + dragOffset.height * 0.3
        } else if index == currentIndex - 1 && dragOffset.height > 0 {
            // Previous card peeks down as we swipe down
            return baseOffset + dragOffset.height * 0.3
        }

        return baseOffset
    }

    private func cardOpacity(for index: Int, currentIndex: Int) -> Double {
        if index == currentIndex {
            return 1.0
        } else if abs(index - currentIndex) == 1 {
            return 0.5
        }
        return 0
    }

    // MARK: - Gesture Handling

    private func handleDragEnd(value: DragGesture.Value) {
        let verticalTranslation = value.translation.height
        let horizontalTranslation = value.translation.width
        let verticalVelocity = value.predictedEndTranslation.height - value.translation.height
        let horizontalVelocity = value.predictedEndTranslation.width - value.translation.width

        // Determine dominant axis
        let isVertical = abs(verticalTranslation) > abs(horizontalTranslation)

        if isVertical {
            // Vertical navigation (articles)
            if verticalTranslation < -swipeThreshold || verticalVelocity < -velocityThreshold {
                // Swipe up - next article
                if viewModel.hasNextArticle {
                    HapticManager.shared.click()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        // Collapse expanded summary when navigating
                        showingExpandedSummary = false
                        expandedSummaryText = ""
                        viewModel.nextArticle()
                        dragOffset = .zero
                    }
                } else {
                    bounceBack()
                }
            } else if verticalTranslation > swipeThreshold || verticalVelocity > velocityThreshold {
                // Swipe down - previous article
                if viewModel.hasPreviousArticle {
                    HapticManager.shared.click()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        // Collapse expanded summary when navigating
                        showingExpandedSummary = false
                        expandedSummaryText = ""
                        viewModel.previousArticle()
                        dragOffset = .zero
                    }
                } else {
                    bounceBack()
                }
            } else {
                bounceBack()
            }
        } else {
            // Horizontal navigation (folders)
            if horizontalTranslation < -swipeThreshold || horizontalVelocity < -velocityThreshold {
                // Swipe left - next folder
                if viewModel.hasNextSource {
                    HapticManager.shared.click()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        // Collapse expanded summary when navigating
                        showingExpandedSummary = false
                        expandedSummaryText = ""
                        viewModel.nextSource()
                        dragOffset = .zero
                    }
                } else {
                    bounceBack()
                }
            } else if horizontalTranslation > swipeThreshold || horizontalVelocity > velocityThreshold {
                // Swipe right - previous folder
                if viewModel.hasPreviousSource {
                    HapticManager.shared.click()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        // Collapse expanded summary when navigating
                        showingExpandedSummary = false
                        expandedSummaryText = ""
                        viewModel.previousSource()
                        dragOffset = .zero
                    }
                } else {
                    bounceBack()
                }
            } else {
                bounceBack()
            }
        }
    }

    private func bounceBack() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragOffset = .zero
        }
    }

    // MARK: - Actions

    private func openInReader(_ article: Article) {
        webLink = WebLink(url: article.link)
    }

    private func shareArticle(_ article: Article) {
        shareItem = article.link
        showingShareSheet = true
    }

    private func expandSummary(for article: Article) {
        // Check if we already have an expanded summary cached
        if let cached = viewModel.expandedSummary(for: article) {
            expandedSummaryText = cached
            currentSummaryStream = nil
            isGeneratingExpanded = false
        } else if !isGeneratingExpanded {
            // Only start if not already generating (prevents spam)
            expandedSummaryText = ""
            isGeneratingExpanded = true

            Task {
                await generateExpandedSummary(for: article)
            }
        }
        // If already generating, do nothing (like short summary approach)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showingExpandedSummary = true
        }
    }

    @MainActor
    private func generateExpandedSummary(for article: Article) async {
        var sawAny = false

        let stream = await ArticleSummarizer.shared.streamSummary(
            url: article.link,
            length: .reelExpanded,
            seedText: article.summary.isEmpty ? nil : article.summary
        )

        var lastUpdate = Date.distantPast
        for await text in stream {
            sawAny = true
            let now = Date()
            if now.timeIntervalSince(lastUpdate) >= 0.05 { // 20hz max throttle
                lastUpdate = now
                expandedSummaryText = text
            }
        }

        // Final update
        if sawAny {
            // Get final cached value
            if let final = await ArticleSummarizer.shared.cachedSummary(for: article.link, length: .reelExpanded) {
                expandedSummaryText = final
                viewModel.cacheExpandedSummary(final, for: article)
            }
        }

        isGeneratingExpanded = false
    }

    private func collapseSummary() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showingExpandedSummary = false
        }
    }

    // MARK: - Loading & Empty States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            Text("Loading articles...")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "newspaper")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.5))

            Text("No Articles")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text("Add some feeds to see articles here")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))

            Button {
                HapticManager.shared.click()
                dismiss()
            } label: {
                Text("Go Back")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
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
