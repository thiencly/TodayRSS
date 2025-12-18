//
//  NewsReelView.swift
//  VibeRSS_Test
//
//  TikTok-style news reel main container view using native ScrollView and TabView paging
//

import SwiftUI
import UIKit

// MARK: - Instagram Reels-style Vertical Pager (Robust UIKit Implementation)

/// Protocol for type-erased coordinator communication
protocol ReelsPagerCoordinator: AnyObject {
    var itemCount: Int { get set }
    var contentBuilder: ((Int) -> AnyView)? { get set }
    var isUserScrolling: Bool { get set }
    var lastReportedIndex: Int { get set }
    func reportPageChange(_ index: Int)
}

struct ReelsVerticalPager<Content: View>: UIViewControllerRepresentable {
    let items: [AnyHashable]
    @Binding var currentIndex: Int
    let content: (Int) -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> ReelsPagerViewController {
        let controller = ReelsPagerViewController()
        controller.coordinator = context.coordinator
        context.coordinator.pagerController = controller
        return controller
    }

    func updateUIViewController(_ controller: ReelsPagerViewController, context: Context) {
        let coordinator = context.coordinator

        // Update items count
        coordinator.itemCount = items.count

        // Update content builders
        coordinator.contentBuilder = { [content] index in
            AnyView(content(index))
        }

        // Reload if needed
        controller.reloadData()

        // Sync current index (only if not user-initiated scroll)
        if !coordinator.isUserScrolling && coordinator.lastReportedIndex != currentIndex {
            controller.scrollToPage(currentIndex, animated: false)
        }
    }

    class Coordinator: NSObject, ReelsPagerCoordinator {
        var parent: ReelsVerticalPager
        weak var pagerController: ReelsPagerViewController?
        var itemCount: Int = 0
        var contentBuilder: ((Int) -> AnyView)?
        var isUserScrolling = false
        var lastReportedIndex: Int = 0

        init(_ parent: ReelsVerticalPager) {
            self.parent = parent
            self.lastReportedIndex = parent.currentIndex
        }

        func reportPageChange(_ index: Int) {
            guard index != lastReportedIndex else { return }
            lastReportedIndex = index
            DispatchQueue.main.async { [weak self] in
                self?.parent.currentIndex = index
            }
        }
    }
}

// MARK: - UIKit Pager View Controller

class ReelsPagerViewController: UIViewController, UIScrollViewDelegate {
    weak var coordinator: (any ReelsPagerCoordinator)?

    private var scrollView: UIScrollView!
    private var contentView: UIView!
    private var pageViews: [Int: UIView] = [:]
    private var hostingControllers: [Int: UIHostingController<AnyView>] = [:]

    private var pageHeight: CGFloat { view.bounds.height }
    private var currentPage: Int = 0
    private var isAnimating = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScrollView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateContentSize()
        layoutVisiblePages()
    }

    private func setupScrollView() {
        scrollView = UIScrollView()
        scrollView.delegate = self
        scrollView.isPagingEnabled = false // We handle paging manually for custom animation
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = true
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func updateContentSize() {
        guard let coordinator = coordinator, pageHeight > 0 else { return }
        let totalHeight = pageHeight * CGFloat(max(1, coordinator.itemCount))

        // Update content view height
        for constraint in contentView.constraints where constraint.firstAttribute == .height {
            constraint.isActive = false
        }
        contentView.heightAnchor.constraint(equalToConstant: totalHeight).isActive = true
    }

    func reloadData() {
        layoutVisiblePages()
    }

    private func layoutVisiblePages() {
        guard let coordinator = coordinator,
              coordinator.itemCount > 0,
              pageHeight > 0,
              let contentBuilder = coordinator.contentBuilder else {
            return
        }

        let visibleRange = calculateVisibleRange()

        // Remove pages outside visible range
        for (index, pageView) in pageViews where !visibleRange.contains(index) {
            pageView.removeFromSuperview()
            pageViews.removeValue(forKey: index)
            hostingControllers.removeValue(forKey: index)
        }

        // Add/update pages in visible range
        for index in visibleRange {
            if pageViews[index] == nil {
                addPage(at: index, contentBuilder: contentBuilder)
            }
            updatePageFrame(at: index)
        }
    }

    private func calculateVisibleRange() -> ClosedRange<Int> {
        guard let coordinator = coordinator, coordinator.itemCount > 0, pageHeight > 0 else {
            return 0...0
        }

        let offsetY = scrollView.contentOffset.y
        let visibleStart = max(0, Int(floor(offsetY / pageHeight)) - 1)
        let visibleEnd = min(coordinator.itemCount - 1, Int(ceil((offsetY + view.bounds.height) / pageHeight)) + 1)

        return visibleStart...max(visibleStart, visibleEnd)
    }

    private func addPage(at index: Int, contentBuilder: (Int) -> AnyView) {
        let content = contentBuilder(index)
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        // Disable safe area insets so content fills the entire page
        hostingController.safeAreaRegions = []

        addChild(hostingController)
        contentView.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        pageViews[index] = hostingController.view
        hostingControllers[index] = hostingController
    }

    private func updatePageFrame(at index: Int) {
        guard let pageView = pageViews[index] else { return }

        let frame = CGRect(
            x: 0,
            y: CGFloat(index) * pageHeight,
            width: view.bounds.width,
            height: pageHeight
        )

        // Remove existing constraints and set frame directly for performance
        pageView.translatesAutoresizingMaskIntoConstraints = true
        pageView.frame = frame
    }

    func scrollToPage(_ page: Int, animated: Bool) {
        guard let coordinator = coordinator,
              page >= 0 && page < coordinator.itemCount,
              pageHeight > 0 else { return }

        let targetOffset = CGFloat(page) * pageHeight

        if animated {
            animateToOffset(targetOffset, velocity: 0)
        } else {
            scrollView.contentOffset.y = targetOffset
            currentPage = page
        }
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        coordinator?.isUserScrolling = true
        isAnimating = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        layoutVisiblePages()
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard let coordinator = coordinator, pageHeight > 0 else { return }

        // Cancel default deceleration - we'll handle it
        targetContentOffset.pointee = scrollView.contentOffset

        let currentOffset = scrollView.contentOffset.y
        let currentPageFloat = currentOffset / pageHeight
        var targetPage = Int(round(currentPageFloat))

        // Determine target page based on velocity
        let velocityThreshold: CGFloat = 0.3
        if velocity.y > velocityThreshold {
            targetPage = Int(floor(currentPageFloat)) + 1
        } else if velocity.y < -velocityThreshold {
            targetPage = Int(ceil(currentPageFloat)) - 1
        }

        // Clamp to valid range
        targetPage = max(0, min(targetPage, coordinator.itemCount - 1))

        let targetOffset = CGFloat(targetPage) * pageHeight
        animateToOffset(targetOffset, velocity: velocity.y)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate && !isAnimating {
            snapToNearestPage()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        coordinator?.isUserScrolling = false
        snapToNearestPage()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        coordinator?.isUserScrolling = false
        updateCurrentPage()
    }

    // MARK: - Custom Animation

    private func animateToOffset(_ targetOffset: CGFloat, velocity: CGFloat) {
        isAnimating = true

        let targetPage = Int(round(targetOffset / pageHeight))

        // Instagram Reels-like spring animation
        UIView.animate(
            withDuration: 0.45,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: min(abs(velocity) * 0.5, 2.0),
            options: [.allowUserInteraction, .curveEaseOut]
        ) { [weak self] in
            self?.scrollView.contentOffset.y = targetOffset
        } completion: { [weak self] finished in
            guard let self = self else { return }
            self.isAnimating = false
            self.coordinator?.isUserScrolling = false
            if finished {
                self.currentPage = targetPage
                self.coordinator?.reportPageChange(targetPage)
                HapticManager.shared.click()
            }
        }
    }

    private func snapToNearestPage() {
        guard let coordinator = coordinator, pageHeight > 0 else { return }

        let currentOffset = scrollView.contentOffset.y
        let targetPage = max(0, min(Int(round(currentOffset / pageHeight)), coordinator.itemCount - 1))
        let targetOffset = CGFloat(targetPage) * pageHeight

        if abs(currentOffset - targetOffset) > 1 {
            animateToOffset(targetOffset, velocity: 0)
        } else {
            currentPage = targetPage
            coordinator.reportPageChange(targetPage)
        }
    }

    private func updateCurrentPage() {
        guard pageHeight > 0 else { return }
        let page = Int(round(scrollView.contentOffset.y / pageHeight))
        if page != currentPage {
            currentPage = page
            coordinator?.reportPageChange(page)
        }
    }
}

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
        .overlay(alignment: .topLeading) {
            // Close button - 44x44pt per Apple HIG
            Button {
                HapticManager.shared.click()
                dismiss()
            } label: {
                GlassEffectContainer {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .padding(.leading, 16)
            .padding(.top, 8)
        }
        .overlay(alignment: .top) {
            // Article counter
            if !viewModel.articles(forSourceAt: selectedSourceIndex).isEmpty {
                GlassEffectContainer {
                    Text("\(viewModel.currentArticleIndex + 1)/\(viewModel.articles(forSourceAt: selectedSourceIndex).count)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .padding(.top, 12)
                .onTapGesture {
                    HapticManager.shared.click()
                    viewModel.currentArticleIndex = 0
                }
            }
        }
        .overlay(alignment: .top) {
            // Folder indicator pills
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
                .padding(.top, 60)
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

// MARK: - Source Page View (Vertical Article Paging with UIKit)

struct SourcePageView: View {
    @ObservedObject var viewModel: NewsReelViewModel
    let sourceIndex: Int
    let onArticleTap: (Article) -> Void
    let onSummaryRetry: (Article) -> Void

    @State private var currentArticleIndex: Int = 0

    private var articles: [Article] {
        viewModel.articles(forSourceAt: sourceIndex)
    }

    var body: some View {
        ReelsVerticalPager(
            items: articles.map { $0.id as AnyHashable },
            currentIndex: $currentArticleIndex
        ) { index in
            articleCard(at: index)
        }
        .ignoresSafeArea()
        .onChange(of: currentArticleIndex) { _, newIndex in
            if sourceIndex == viewModel.currentSourceIndex {
                viewModel.currentArticleIndex = newIndex
            }
            // Generate summary for newly visible article
            if newIndex >= 0 && newIndex < articles.count {
                let article = articles[newIndex]
                Task {
                    await viewModel.generateReelSummary(for: article)
                }
            }
        }
        .onAppear {
            // Generate summary for first article
            if let firstArticle = articles.first {
                Task {
                    await viewModel.generateReelSummary(for: firstArticle)
                }
            }
        }
    }

    @ViewBuilder
    private func articleCard(at index: Int) -> some View {
        if index >= 0 && index < articles.count {
            let article = articles[index]
            NewsReelCardView(
                article: article,
                reelSummary: viewModel.reelSummary(for: article),
                isLoadingSummary: viewModel.isSummaryLoading(for: article),
                isRetryingSummary: viewModel.isSummaryRetrying(for: article),
                hasSummaryFailed: viewModel.hasSummaryFailed(for: article),
                onTitleTap: { onArticleTap(article) },
                onRetryTap: { onSummaryRetry(article) }
            )
            .onTapGesture {
                HapticManager.shared.click()
                onArticleTap(article)
            }
        } else {
            Color.black
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
