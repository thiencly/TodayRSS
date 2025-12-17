//
//  NewsReelView.swift
//  VibeRSS_Test
//
//  TikTok-style news reel main container view
//

import SwiftUI

struct NewsReelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: FeedStore
    @StateObject private var viewModel = NewsReelViewModel()

    // Gesture and navigation state
    @State private var dragOffset: CGSize = .zero
    @State private var lockedAxis: Axis? = nil  // Lock to vertical or horizontal once determined
    @State private var dragStartOffset: CGSize = .zero  // Offset when axis was locked
    @State private var showingExpandedSummary: Bool = false
    @State private var expandedSummaryText: String = ""
    @State private var currentSummaryStream: AsyncStream<String>?

    // Sharing
    @State private var shareItem: URL?
    @State private var showingShareSheet: Bool = false

    // Reader mode
    @State private var webLink: WebLink?

    @State private var isGeneratingExpanded: Bool = false
    @State private var isRefreshing: Bool = false

    // Gesture thresholds
    private let swipeThreshold: CGFloat = 50
    private let velocityThreshold: CGFloat = 300

    // Horizontal transition for topic changes
    @State private var horizontalOffset: CGFloat = 0

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
                    if !viewModel.currentArticles.isEmpty {
                        Button {
                            HapticManager.shared.click()
                            jumpToFirstArticle()
                        } label: {
                            Text("\(viewModel.currentArticleIndex + 1)/\(viewModel.currentArticles.count)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .glassEffect(.regular.interactive())
                        }
                        .buttonStyle(.plain)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.currentArticle != nil {
                        HStack(spacing: 16) {
                            Button {
                                HapticManager.shared.click()
                                refreshArticles()
                            } label: {
                                Group {
                                    if isRefreshing {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                }
                                .frame(width: 20, height: 20)
                            }
                            .disabled(isRefreshing)

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
        }
        .overlay(alignment: .top) {
            // Folder indicator pills below toolbar
            if viewModel.sources.count > 1 {
                FolderIndicatorView(
                    sources: viewModel.sources,
                    selectedIndex: Binding(
                        get: { viewModel.currentSourceIndex },
                        set: { _ in } // Handled by onSelect
                    ),
                    onSelect: { newIndex in
                        transitionToSource(at: newIndex, screenWidth: UIScreen.main.bounds.width)
                    }
                )
                .padding(.top, 52)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.initialize(folders: store.folders, feeds: store.feeds)
        }
        .onChange(of: viewModel.currentSourceIndex) { _, _ in
            // Preload adjacent sources when source changes
            Task {
                await viewModel.preloadAdjacentSources()
            }
        }
        .task {
            // Preload adjacent sources after initial load
            try? await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5s for initial load
            await viewModel.preloadAdjacentSources()
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

    /// Indices of sources to render (current ± 1)
    private var visibleSourceIndices: [Int] {
        let current = viewModel.currentSourceIndex
        var indices: [Int] = []
        if current > 0 {
            indices.append(current - 1)
        }
        indices.append(current)
        if current < viewModel.sources.count - 1 {
            indices.append(current + 1)
        }
        return indices
    }

    @ViewBuilder
    private func articleCardsView(geometry: GeometryProxy) -> some View {
        let screenWidth = geometry.size.width
        let currentIdx = viewModel.currentSourceIndex

        ZStack {
            ForEach(visibleSourceIndices, id: \.self) { sourceIdx in
                let relativePosition = sourceIdx - currentIdx
                let xOffset = CGFloat(relativePosition) * screenWidth + horizontalOffset + dragOffset.width

                sourceContentView(
                    sourceIndex: sourceIdx,
                    geometry: geometry
                )
                .offset(x: xOffset)
            }
        }
        .ignoresSafeArea()
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let translation = value.translation

                    // Use local variables since @State doesn't update until next render
                    var effectiveAxis = lockedAxis
                    var effectiveStartOffset = dragStartOffset

                    // Lock to an axis once there's enough movement to determine direction
                    if effectiveAxis == nil {
                        // Reset dragOffset immediately to cancel any ongoing animation from previous gesture
                        if dragOffset != .zero {
                            dragOffset = .zero
                        }

                        let dominated = max(abs(translation.width), abs(translation.height))
                        if dominated > 10 {
                            effectiveAxis = abs(translation.width) > abs(translation.height) ? .horizontal : .vertical
                            lockedAxis = effectiveAxis  // Update state for next frame
                            // Capture the translation at the moment of axis lock
                            // This prevents jumping to catch up to finger position
                            dragStartOffset = translation
                            effectiveStartOffset = translation
                        }
                    }

                    // Apply offset only on locked axis, starting from where we locked
                    if effectiveAxis == .horizontal {
                        let adjustedWidth = translation.width - effectiveStartOffset.width
                        dragOffset = CGSize(width: adjustedWidth, height: 0)
                    } else if effectiveAxis == .vertical {
                        var adjustedHeight = translation.height - effectiveStartOffset.height

                        // Prevent swiping down when at first article
                        if !viewModel.hasPreviousArticle && adjustedHeight > 0 {
                            adjustedHeight = 0
                        }
                        // Prevent swiping up when at last article
                        if !viewModel.hasNextArticle && adjustedHeight < 0 {
                            adjustedHeight = 0
                        }

                        dragOffset = CGSize(width: 0, height: adjustedHeight)
                    }
                    // Before axis is locked, dragOffset stays at previous value (typically .zero after last gesture)
                }
                .onEnded { value in
                    handleDragEnd(value: value, screenWidth: screenWidth)
                    lockedAxis = nil  // Reset for next gesture
                    dragStartOffset = .zero  // Reset start offset
                }
        )
    }

    @ViewBuilder
    private func sourceContentView(sourceIndex: Int, geometry: GeometryProxy) -> some View {
        let articles = viewModel.articles(forSourceAt: sourceIndex)
        let currentArticleIndex = sourceIndex == viewModel.currentSourceIndex ? viewModel.currentArticleIndex : 0
        let screenHeight = geometry.size.height
        let verticalDrag = dragOffset.height

        ZStack {
            ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                if abs(index - currentArticleIndex) <= 1 {
                    let isCurrentArticle = index == currentArticleIndex && sourceIndex == viewModel.currentSourceIndex
                    // Calculate offset inline like horizontal does
                    let baseOffset = CGFloat(index - currentArticleIndex) * screenHeight
                    let yOffset = baseOffset + verticalDrag

                    NewsReelCardView(
                        article: article,
                        reelSummary: viewModel.reelSummary(for: article),
                        isLoadingSummary: viewModel.isSummaryLoading(for: article),
                        isRetryingSummary: viewModel.isSummaryRetrying(for: article),
                        hasSummaryFailed: viewModel.hasSummaryFailed(for: article),
                        isExpanded: isCurrentArticle && showingExpandedSummary,
                        expandedSummary: isCurrentArticle ? expandedSummaryText : "",
                        isStreamingSummary: isCurrentArticle && isGeneratingExpanded,
                        summaryLength: "long",
                        onTitleTap: { openInReader(article) },
                        onSummaryTap: { expandSummary(for: article) },
                        onCollapseTap: { collapseSummary() },
                        onRetryTap: {
                            Task {
                                await viewModel.retryReelSummary(for: article)
                            }
                        }
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .offset(y: yOffset)
                    .opacity(index == currentArticleIndex ? 1.0 : 0.5)
                    .zIndex(index == currentArticleIndex ? 1 : 0)
                    .onAppear {
                        Task {
                            await viewModel.generateReelSummary(for: article)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDragEnd(value: DragGesture.Value, screenWidth: CGFloat) {
        // Use adjusted offset values (already accounting for dragStartOffset)
        let verticalTranslation = dragOffset.height
        let horizontalTranslation = dragOffset.width
        let verticalVelocity = value.predictedEndTranslation.height - value.translation.height
        let horizontalVelocity = value.predictedEndTranslation.width - value.translation.width

        // Use locked axis instead of comparing magnitudes (axis was already determined)
        let isVertical = lockedAxis == .vertical

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
                    transitionToNextSource(screenWidth: screenWidth)
                } else {
                    bounceBack()
                }
            } else if horizontalTranslation > swipeThreshold || horizontalVelocity > velocityThreshold {
                // Swipe right - previous folder
                if viewModel.hasPreviousSource {
                    transitionToPreviousSource(screenWidth: screenWidth)
                } else {
                    bounceBack()
                }
            } else {
                bounceBack()
            }
        }
    }

    private func transitionToNextSource(screenWidth: CGFloat) {
        HapticManager.shared.click()
        showingExpandedSummary = false
        expandedSummaryText = ""

        // Animate sliding left by one screen width
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            horizontalOffset = -screenWidth
            dragOffset = .zero
        }

        // After animation completes, change source and reset offset atomically without animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                viewModel.nextSource()
                horizontalOffset = 0
            }
        }
    }

    private func transitionToPreviousSource(screenWidth: CGFloat) {
        HapticManager.shared.click()
        showingExpandedSummary = false
        expandedSummaryText = ""

        // Animate sliding right by one screen width
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            horizontalOffset = screenWidth
            dragOffset = .zero
        }

        // After animation completes, change source and reset offset atomically without animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                viewModel.previousSource()
                horizontalOffset = 0
            }
        }
    }

    private func transitionToSource(at index: Int, screenWidth: CGFloat) {
        let currentIndex = viewModel.currentSourceIndex
        guard index != currentIndex else { return }

        HapticManager.shared.click()
        showingExpandedSummary = false
        expandedSummaryText = ""

        let steps = abs(index - currentIndex)

        if steps == 1 {
            // Adjacent source - smooth slide animation
            let targetOffset = index > currentIndex ? -screenWidth : screenWidth

            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                horizontalOffset = targetOffset
                dragOffset = .zero
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    viewModel.selectSource(at: index)
                    horizontalOffset = 0
                }
            }
        } else {
            // Multi-step jump - just change source directly
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragOffset = .zero
                viewModel.selectSource(at: index)
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

    private func jumpToFirstArticle() {
        guard viewModel.currentArticleIndex > 0 else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showingExpandedSummary = false
            expandedSummaryText = ""
            viewModel.currentArticleIndex = 0
            dragOffset = .zero
        }
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
