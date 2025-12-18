//
//  NewsReelView.swift
//  VibeRSS_Test
//
//  TikTok-style news reel main container view
//

import SwiftUI
import QuartzCore

// MARK: - CADisplayLink Helper

/// Helper class to use CADisplayLink with a closure (since CADisplayLink requires @objc selector)
final class DisplayLinkTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func handleDisplayLink(_ displayLink: CADisplayLink) {
        handler()
    }
}

struct NewsReelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: FeedStore
    @StateObject private var viewModel = NewsReelViewModel()

    // Gesture and navigation state
    @State private var dragOffset: CGSize = .zero
    @State private var lockedAxis: Axis? = nil
    @State private var lockPointTranslation: CGSize = .zero

    // Sharing
    @State private var shareItem: URL?
    @State private var showingShareSheet: Bool = false

    // Reader mode
    @State private var webLink: WebLink?

    @State private var isRefreshing: Bool = false
    @State private var isAnimating: Bool = false  // Track if manual animation is running
    @State private var displayLink: CADisplayLink?
    @State private var displayLinkTarget: DisplayLinkTarget?
    @State private var animationStartTime: CFTimeInterval = 0
    @State private var animationStartOffset: CGSize = .zero
    @State private var animationTargetOffset: CGSize = .zero
    @State private var animationStartHorizontal: CGFloat = 0
    @State private var animationTargetHorizontal: CGFloat = 0
    @State private var animationIsHorizontal: Bool = false
    @State private var animationCompletion: (() -> Void)?

    // Gesture thresholds
    private let swipeThreshold: CGFloat = 50
    private let velocityThreshold: CGFloat = 300
    private let animationDuration: CFTimeInterval = 0.25  // Manual animation duration

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
        .onDisappear {
            // Clean up CADisplayLink
            stopDisplayLink()
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
        .sheet(item: $webLink) { w in
            ArticleReaderView(url: w.url, articleTitle: nil, articleDate: w.date)
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 15)
                .onChanged { value in
                    guard !isAnimating else { return }

                    let translation = value.translation

                    // If axis not locked yet, check if we should lock
                    if lockedAxis == nil {
                        let threshold: CGFloat = 10
                        if abs(translation.width) > threshold || abs(translation.height) > threshold {
                            // Lock to the dominant axis
                            if abs(translation.height) > abs(translation.width) {
                                lockedAxis = .vertical
                            } else {
                                lockedAxis = .horizontal
                            }
                            // Remember where we locked - movement starts from here
                            lockPointTranslation = translation
                        }
                        // Don't move UI until axis is locked
                        return
                    }

                    // Apply movement only in locked axis, relative to lock point
                    if lockedAxis == .vertical {
                        dragOffset = CGSize(width: 0, height: translation.height - lockPointTranslation.height)
                    } else {
                        dragOffset = CGSize(width: translation.width - lockPointTranslation.width, height: 0)
                    }
                }
                .onEnded { value in
                    let axis = lockedAxis
                    lockedAxis = nil
                    lockPointTranslation = .zero

                    guard axis != nil else {
                        // No axis was locked (tiny gesture), just reset
                        dragOffset = .zero
                        return
                    }

                    handleDragEnd(translation: dragOffset, predictedEnd: value.predictedEndTranslation, screenWidth: screenWidth, screenHeight: geometry.size.height, axis: axis!)
                }
        )
    }

    @ViewBuilder
    private func sourceContentView(sourceIndex: Int, geometry: GeometryProxy) -> some View {
        let articles = viewModel.articles(forSourceAt: sourceIndex)
        let currentArticleIndex = sourceIndex == viewModel.currentSourceIndex ? viewModel.currentArticleIndex : 0
        let screenHeight = geometry.size.height

        // Calculate opacity based on drag progress - fade in the next card as we swipe
        let dragProgress = abs(dragOffset.height) / screenHeight  // 0 to 1
        let isSwipingUp = dragOffset.height < 0
        let isSwipingDown = dragOffset.height > 0

        ZStack {
            ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                if abs(index - currentArticleIndex) <= 1 {
                    let isCurrentArticle = index == currentArticleIndex && sourceIndex == viewModel.currentSourceIndex
                    let baseOffset = CGFloat(index - currentArticleIndex) * screenHeight

                    // Calculate dynamic opacity based on swipe progress
                    let cardOpacity: Double = {
                        if index == currentArticleIndex {
                            // Current card fades out as we drag
                            return 1.0 - (dragProgress * 0.5)
                        } else if index == currentArticleIndex + 1 && isSwipingUp {
                            // Next card fades in as we swipe up
                            return 0.5 + (dragProgress * 0.5)
                        } else if index == currentArticleIndex - 1 && isSwipingDown {
                            // Previous card fades in as we swipe down
                            return 0.5 + (dragProgress * 0.5)
                        } else {
                            return 0.5
                        }
                    }()

                    NewsReelCardView(
                        article: article,
                        reelSummary: viewModel.reelSummary(for: article),
                        isLoadingSummary: viewModel.isSummaryLoading(for: article),
                        isRetryingSummary: viewModel.isSummaryRetrying(for: article),
                        hasSummaryFailed: viewModel.hasSummaryFailed(for: article),
                        onTitleTap: { openInReader(article) },
                        onRetryTap: {
                            Task {
                                await viewModel.retryReelSummary(for: article)
                            }
                        }
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticManager.shared.click()
                        openInReader(article)
                    }
                    .offset(y: baseOffset)
                    .opacity(cardOpacity)
                    .zIndex(index == currentArticleIndex ? 1 : 0)
                    .onAppear {
                        Task {
                            await viewModel.generateReelSummary(for: article)
                        }
                    }
                }
            }
        }
        .offset(y: dragOffset.height)
    }

    // MARK: - Gesture Handling

    private func handleDragEnd(translation: CGSize, predictedEnd: CGSize, screenWidth: CGFloat, screenHeight: CGFloat, axis: Axis) {
        // Don't process if already animating
        guard !isAnimating else { return }

        let verticalTranslation = translation.height
        let horizontalTranslation = translation.width
        let verticalVelocity = predictedEnd.height - translation.height
        let horizontalVelocity = predictedEnd.width - translation.width

        let isVertical = axis == .vertical

        if isVertical {
            // Vertical navigation (articles)
            if verticalTranslation < -swipeThreshold || verticalVelocity < -velocityThreshold {
                // Swipe up - next article
                if viewModel.hasNextArticle {
                    HapticManager.shared.click()
                    animateOffset(to: CGSize(width: 0, height: -screenHeight)) {
                        dragOffset = .zero
                        viewModel.nextArticle()
                    }
                } else {
                    animateBounceBack()
                }
            } else if verticalTranslation > swipeThreshold || verticalVelocity > velocityThreshold {
                // Swipe down - previous article
                if viewModel.hasPreviousArticle {
                    HapticManager.shared.click()
                    animateOffset(to: CGSize(width: 0, height: screenHeight)) {
                        dragOffset = .zero
                        viewModel.previousArticle()
                    }
                } else {
                    animateBounceBack()
                }
            } else {
                animateBounceBack()
            }
        } else {
            // Horizontal navigation (folders)
            if horizontalTranslation < -swipeThreshold || horizontalVelocity < -velocityThreshold {
                // Swipe left - next folder
                if viewModel.hasNextSource {
                    transitionToNextSource(screenWidth: screenWidth)
                } else {
                    animateBounceBack()
                }
            } else if horizontalTranslation > swipeThreshold || horizontalVelocity > velocityThreshold {
                // Swipe right - previous folder
                if viewModel.hasPreviousSource {
                    transitionToPreviousSource(screenWidth: screenWidth)
                } else {
                    animateBounceBack()
                }
            } else {
                animateBounceBack()
            }
        }
    }

    private func transitionToNextSource(screenWidth: CGFloat) {
        HapticManager.shared.click()
        animateHorizontalOffset(to: -screenWidth) {
            viewModel.nextSource()
            horizontalOffset = 0
        }
    }

    private func transitionToPreviousSource(screenWidth: CGFloat) {
        HapticManager.shared.click()
        animateHorizontalOffset(to: screenWidth) {
            viewModel.previousSource()
            horizontalOffset = 0
        }
    }

    private func transitionToSource(at index: Int, screenWidth: CGFloat) {
        let currentIndex = viewModel.currentSourceIndex
        guard index != currentIndex else { return }

        HapticManager.shared.click()

        // Only animate for adjacent sources, otherwise switch directly
        let isAdjacent = abs(index - currentIndex) == 1

        if isAdjacent {
            let targetOffset = index > currentIndex ? -screenWidth : screenWidth
            animateHorizontalOffset(to: targetOffset) {
                viewModel.selectSource(at: index)
                horizontalOffset = 0
            }
        } else {
            // Direct switch for non-adjacent sources
            viewModel.selectSource(at: index)
        }
    }

    // MARK: - Actions

    private func openInReader(_ article: Article) {
        webLink = WebLink(url: article.link, date: article.pubDate)
    }

    private func shareArticle(_ article: Article) {
        shareItem = article.link
        showingShareSheet = true
    }

    private func jumpToFirstArticle() {
        guard viewModel.currentArticleIndex > 0 else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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

    // MARK: - Manual Animation (CADisplayLink - syncs with display refresh)

    /// Animates dragOffset from current value to target using CADisplayLink
    /// This bypasses SwiftUI's withAnimation and syncs perfectly with the display refresh rate
    private func animateOffset(to target: CGSize, completion: @escaping () -> Void) {
        stopDisplayLink()

        isAnimating = true
        animationIsHorizontal = false
        animationStartTime = CACurrentMediaTime()
        animationStartOffset = dragOffset
        animationTargetOffset = target
        animationCompletion = completion

        startDisplayLink()
    }

    /// Animates horizontalOffset using CADisplayLink
    private func animateHorizontalOffset(to target: CGFloat, completion: @escaping () -> Void) {
        stopDisplayLink()

        isAnimating = true
        animationIsHorizontal = true
        animationStartTime = CACurrentMediaTime()
        animationStartHorizontal = horizontalOffset
        animationTargetHorizontal = target
        animationStartOffset = dragOffset  // Also animate dragOffset to zero
        animationTargetOffset = .zero
        animationCompletion = completion

        startDisplayLink()
    }

    /// Simple bounce back animation
    private func animateBounceBack() {
        animateOffset(to: .zero) { }
    }

    /// Creates and starts the CADisplayLink
    private func startDisplayLink() {
        let target = DisplayLinkTarget { [self] in
            handleDisplayLinkFrame()
        }
        displayLinkTarget = target

        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.handleDisplayLink(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Stops and cleans up the CADisplayLink
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkTarget = nil
    }

    /// Called each frame by CADisplayLink
    private func handleDisplayLinkFrame() {
        let elapsed = CACurrentMediaTime() - animationStartTime
        let progress = min(elapsed / animationDuration, 1.0)

        // Ease-out cubic function: 1 - (1 - t)^3
        let easedProgress = 1 - pow(1 - progress, 3)

        if animationIsHorizontal {
            // Horizontal animation
            let newHorizontal = animationStartHorizontal + (animationTargetHorizontal - animationStartHorizontal) * easedProgress
            let newDragWidth = animationStartOffset.width * (1 - easedProgress)
            let newDragHeight = animationStartOffset.height * (1 - easedProgress)

            horizontalOffset = newHorizontal
            dragOffset = CGSize(width: newDragWidth, height: newDragHeight)

            if progress >= 1.0 {
                stopDisplayLink()
                horizontalOffset = animationTargetHorizontal
                dragOffset = .zero
                isAnimating = false
                animationCompletion?()
                animationCompletion = nil
            }
        } else {
            // Vertical animation
            let newWidth = animationStartOffset.width + (animationTargetOffset.width - animationStartOffset.width) * easedProgress
            let newHeight = animationStartOffset.height + (animationTargetOffset.height - animationStartOffset.height) * easedProgress

            dragOffset = CGSize(width: newWidth, height: newHeight)

            if progress >= 1.0 {
                stopDisplayLink()
                dragOffset = animationTargetOffset
                isAnimating = false
                animationCompletion?()
                animationCompletion = nil
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
                Text("Go Back")
                    .font(.roundedHeadline)
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
