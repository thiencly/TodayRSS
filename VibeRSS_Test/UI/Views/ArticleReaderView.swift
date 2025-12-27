//
//  ArticleReaderView.swift
//  VibeRSS_Test
//
//  Custom reader view for displaying article content using Reeeed extraction
//

import SwiftUI
import WebKit
import Reeeed
import SafariServices

// MARK: - WebView Font Size Manager
final class ReaderWebViewManager {
    static let shared = ReaderWebViewManager()
    private init() {}

    var currentWebView: WKWebView?

    func updateFontSize(_ fontSize: Double) {
        guard let webView = currentWebView else {
            print("ReaderWebViewManager: No webView available")
            return
        }
        let js = """
        (function() {
            var style = document.getElementById('dynamic-font-size');
            if (!style) {
                style = document.createElement('style');
                style.id = 'dynamic-font-size';
                document.head.appendChild(style);
            }
            style.textContent = `
                body { font-size: \(fontSize)px !important; }
                p, li, td, th { font-size: \(fontSize)px !important; }
                h1 { font-size: \(fontSize + 6)px !important; }
                h2 { font-size: \(fontSize + 4)px !important; }
                h3 { font-size: \(fontSize + 2)px !important; }
            `;
        })();
        """
        DispatchQueue.main.async {
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("ReaderWebViewManager: JS error - \(error)")
                }
            }
        }
    }
}

// MARK: - Article Reader View

struct ArticleReaderView: View {
    let url: URL
    let articleTitle: String?
    let articleDate: Date?
    let thumbnailURL: URL?
    let sourceIconURL: URL?
    let sourceTitle: String?

    init(url: URL, articleTitle: String?, articleDate: Date? = nil, thumbnailURL: URL? = nil, sourceIconURL: URL? = nil, sourceTitle: String? = nil) {
        self.url = url
        self.articleTitle = articleTitle
        self.articleDate = articleDate
        self.thumbnailURL = thumbnailURL
        self.sourceIconURL = sourceIconURL
        self.sourceTitle = sourceTitle
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var extractedContent: Reeeed.FetchAndExtractionResult?
    @State private var cachedStyledHTML: String?  // For offline cached HTML content
    @State private var cachedBaseURL: URL?
    @State private var cachedPlainText: String?   // For offline text-only content
    @State private var isOfflineMode: Bool = false
    @State private var isLoading = true
    @State private var error: String?
    @State private var showSettings = false
    @State private var isSaved: Bool = false
    @State private var isGeneratingSummary = false
    @State private var summaryText: String = ""
    @State private var showingSummary = false  // Toggle between article and summary view
    @State private var showSafariView = false
    @AppStorage("readerFontSize") private var fontSize: Double = 18

    // Format date as relative time string
    private var relativeDate: String? {
        guard let date = articleDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                if isLoading {
                    loadingView
                } else if let error = error {
                    errorView(error)
                } else if showingSummary {
                    // Show summary view
                    summaryContentView
                } else if isOfflineMode, let plainText = cachedPlainText {
                    // Display text-only cached content (offline mode)
                    textOnlyArticleView(text: plainText)
                } else if let content = extractedContent {
                    articleWebView(content)
                } else if let styledHTML = cachedStyledHTML {
                    // Display cached HTML content (offline mode)
                    cachedArticleWebView(styledHTML: styledHTML, baseURL: cachedBaseURL)
                }
            }
            .navigationTitle(sourceTitle ?? url.host ?? "Article")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .tint(.primary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    // Font size overlay (above toolbar)
                    if showSettings {
                        fontSizeOverlay
                    }

                    // Toolbar
                    HStack {
                        Spacer()
                        floatingToolbar
                    }
                    .padding(.trailing, 16)
                }
                .padding(.bottom, 8)
                .animation(.easeOut(duration: 0.2), value: showSettings)
            }
        }
        .task {
            await loadArticle()
        }
        .onAppear {
            isSaved = SavedArticlesManager.shared.isSaved(url: url)
        }
        .fullScreenCover(isPresented: $showSafariView) {
            SafariReaderView(url: url)
                .ignoresSafeArea()
        }
    }

    // MARK: - Floating Toolbar

    private var floatingToolbar: some View {
        HStack(spacing: 0) {
            // Summarize button
            Button {
                handleSummarizeButtonTap()
            } label: {
                Group {
                    if isGeneratingSummary {
                        ProgressView()
                            .tint(.primary)
                    } else {
                        Image(systemName: showingSummary ? "doc.text" : "sparkles")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassToolbarButtonStyle())
            .contentTransition(.symbolEffect(.replace))
            .disabled(extractedContent == nil && cachedStyledHTML == nil && cachedPlainText == nil)

            // Save button
            Button {
                toggleSaved()
            } label: {
                Image(systemName: isSaved ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isSaved ? .red : .primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassToolbarButtonStyle())
            .contentTransition(.symbolEffect(.replace))

            // Text size button
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassToolbarButtonStyle())

            // Safari button
            Button {
                showSafariView = true
            } label: {
                Image(systemName: "safari")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassToolbarButtonStyle())

            // Share button
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassToolbarButtonStyle())

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassToolbarButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .overlay {
            if isGeneratingSummary {
                AppleIntelligenceGlow<Capsule>(
                    shape: Capsule(),
                    isActive: true,
                    showIdle: false,
                    scale: 1.0
                )
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.95)).animation(.easeOut(duration: 0.3)))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isGeneratingSummary)
    }

    // MARK: - Summarize Button Action

    private func handleSummarizeButtonTap() {
        HapticManager.shared.click()
        if showingSummary && !summaryText.isEmpty && !isGeneratingSummary {
            // Toggle back to article
            withAnimation(.easeInOut(duration: 0.3)) {
                showingSummary = false
            }
        } else if !isGeneratingSummary {
            // Generate or show summary
            Task { await generateSummary() }
        }
    }

    private func toggleSaved() {
        HapticManager.shared.click()
        let title = articleTitle ?? extractedContent?.extracted.title ?? url.host ?? "Article"
        SavedArticlesManager.shared.toggleSaved(
            url: url,
            title: title,
            pubDate: articleDate,
            thumbnailURL: thumbnailURL,
            sourceIconURL: sourceIconURL,
            sourceTitle: sourceTitle
        )
        isSaved = SavedArticlesManager.shared.isSaved(url: url)
    }

    // MARK: - Subviews

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.98)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color(white: 0.6) : Color(white: 0.45)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading article...")
                .font(.subheadline)
                .foregroundStyle(secondaryTextColor)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Unable to load article")
                .font(.roundedHeadline)
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                Task { await loadArticle() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.roundedHeadline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }

            Button {
                // Fall back to Safari
                UIApplication.shared.open(url)
            } label: {
                Text("Open in Safari")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func articleWebView(_ content: Reeeed.FetchAndExtractionResult) -> some View {
        ReeeederWebView(
            styledHTML: content.styledHTML,
            baseURL: content.baseURL,
            fontSize: $fontSize,
            colorScheme: colorScheme,
            relativeDate: relativeDate
        )
        .ignoresSafeArea()
    }

    /// Display cached article content (for offline reading)
    private func cachedArticleWebView(styledHTML: String, baseURL: URL?) -> some View {
        ReeeederWebView(
            styledHTML: styledHTML,
            baseURL: baseURL,
            fontSize: $fontSize,
            colorScheme: colorScheme,
            relativeDate: relativeDate
        )
        .ignoresSafeArea()
    }

    /// Display text-only cached content (for offline reading when HTML cache unavailable)
    private func textOnlyArticleView(text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Offline indicator
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                    Text("Offline Mode")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())

                // Article title
                if let title = articleTitle {
                    Text(title)
                        .font(.system(.title, design: .serif, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                }

                // Source badge and date
                HStack(spacing: 8) {
                    if let iconURL = sourceIconURL {
                        AsyncImage(url: iconURL) { image in
                            image.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if let source = sourceTitle {
                        Text(source.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(secondaryTextColor)
                    }

                    if let date = relativeDate {
                        Text("·")
                            .foregroundStyle(secondaryTextColor.opacity(0.5))
                        Text(date)
                            .font(.caption)
                            .foregroundStyle(secondaryTextColor)
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                // Article text
                Text(text)
                    .font(.system(size: fontSize))
                    .lineSpacing(6)
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .background(backgroundColor)
    }

    private var fontSizeOverlay: some View {
        HStack(spacing: 0) {
            Button {
                if fontSize > 14 {
                    let newSize = fontSize - 2
                    fontSize = newSize
                    ReaderWebViewManager.shared.updateFontSize(newSize)
                }
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassToolbarButtonStyle())

            Text("\(Int(fontSize))")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 50)

            Button {
                if fontSize < 28 {
                    let newSize = fontSize + 2
                    fontSize = newSize
                    ReaderWebViewManager.shared.updateFontSize(newSize)
                }
            } label: {
                Image(systemName: "textformat.size.larger")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassToolbarButtonStyle())

            Rectangle()
                .fill(Color.primary.opacity(0.3))
                .frame(width: 1, height: 24)
                .padding(.horizontal, 8)

            Button {
                showSettings = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassToolbarButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var summaryContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with sparkle icon
                HStack(spacing: 10) {
                    AnimatedGradientSparkle()
                    Text("Summary")
                        .font(.system(.title, design: .rounded, weight: .bold))
                }
                .padding(.top, 20)

                // Article title
                if let title = articleTitle ?? extractedContent?.extracted.title {
                    Text(title)
                        .font(.system(.title2, design: .default, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                }

                // Summary text with streaming effect
                if summaryText.isEmpty && isGeneratingSummary {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Generating summary...")
                            .foregroundStyle(secondaryTextColor)
                    }
                    .padding(.top, 8)
                } else {
                    Text(summaryText)
                        .font(.system(size: fontSize + 2))
                        .lineSpacing(6)
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
        .background(backgroundColor)
    }

    private func generateSummary() async {
        // Get article text from either live content, HTML cache, or text cache
        let articleText: String
        if let content = extractedContent {
            articleText = await ArticleSummarizer.shared.extractReadableText(from: content.styledHTML)
        } else if let cached = cachedStyledHTML {
            articleText = await ArticleSummarizer.shared.extractReadableText(from: cached)
        } else if let plainText = cachedPlainText {
            articleText = plainText
        } else {
            return
        }

        // Check for cached summary first
        if let cached = await ArticleSummarizer.shared.cachedSummary(for: url, length: .detailed) {
            summaryText = cached
            withAnimation(.easeInOut(duration: 0.3)) {
                showingSummary = true
            }
            return
        }

        summaryText = ""
        withAnimation(.easeInOut(duration: 0.3)) {
            isGeneratingSummary = true
            showingSummary = true
        }

        // Stream the summary with throttled UI updates (max ~20hz to stay under 32hz limit)
        let stream = await ArticleSummarizer.shared.streamSummaryFromText(
            url: url,
            articleText: articleText,
            length: .detailed
        )

        var lastUpdateTime = Date.distantPast
        var latestText = ""
        let throttleInterval: TimeInterval = 0.1  // 100ms = 10hz (lower to avoid rate-limit with concurrent animations)

        for await partial in stream {
            latestText = partial
            let now = Date()
            if now.timeIntervalSince(lastUpdateTime) >= throttleInterval {
                lastUpdateTime = now
                summaryText = latestText
            }
        }

        // Final update to ensure we have the complete text
        await MainActor.run {
            summaryText = latestText
            withAnimation(.easeOut(duration: 0.4)) {
                isGeneratingSummary = false
            }
        }
    }

    // MARK: - Data Loading

    private func loadArticle() async {
        isLoading = true
        error = nil
        isOfflineMode = false

        // Check for cached HTML content first (for offline reading)
        if let cached = await ArticleContentCache.shared.cachedContent(for: url) {
            // Try to fetch fresh content first
            do {
                let theme = createTheme()
                let result = try await Reeeed.fetchAndExtractContent(fromURL: url, theme: theme)

                await MainActor.run {
                    self.extractedContent = result
                    self.isLoading = false
                }

                // Update HTML cache with fresh content
                let updatedCache = CachedArticleContent(
                    styledHTML: result.styledHTML,
                    baseURL: result.baseURL,
                    title: result.extracted.title,
                    timestamp: Date()
                )
                await ArticleContentCache.shared.storeContent(updatedCache, for: url)

                // Also cache extracted text for offline reading
                await cacheArticleText(from: result.styledHTML)
            } catch {
                // Network failed - use cached HTML content
                await MainActor.run {
                    self.cachedStyledHTML = cached.styledHTML
                    self.cachedBaseURL = cached.baseURL
                    self.isLoading = false
                }
            }
            return
        }

        // No HTML cache - try to fetch from network
        do {
            let theme = createTheme()
            let result = try await Reeeed.fetchAndExtractContent(fromURL: url, theme: theme)

            await MainActor.run {
                self.extractedContent = result
                self.isLoading = false
            }

            // Cache the HTML content for offline reading
            let cached = CachedArticleContent(
                styledHTML: result.styledHTML,
                baseURL: result.baseURL,
                title: result.extracted.title,
                timestamp: Date()
            )
            await ArticleContentCache.shared.storeContent(cached, for: url)

            // Also cache extracted text for offline reading
            await cacheArticleText(from: result.styledHTML)
        } catch {
            // Network failed - check for text-only cache as fallback
            if let cachedText = await ArticleTextCache.shared.cachedText(for: url) {
                await MainActor.run {
                    self.cachedPlainText = cachedText
                    self.isOfflineMode = true
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    /// Cache extracted text for offline reading
    private func cacheArticleText(from styledHTML: String) async {
        let articleText = ArticleSummarizer.shared.extractReadableText(from: styledHTML)
        if !articleText.isEmpty {
            await ArticleTextCache.shared.storeText(
                articleText,
                for: url,
                title: articleTitle,
                sourceTitle: sourceTitle,
                pubDate: articleDate
            )
        }
    }

    private func createTheme() -> ReaderTheme {
        let isDark = colorScheme == .dark

        // Create custom CSS with Apple fonts
        // SF Pro for body, SF Pro Rounded for titles
        let customCSS = """
        body {
            font-size: \(fontSize)px !important;
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif !important;
            -webkit-font-smoothing: antialiased;
        }
        p, li, td, th {
            font-size: \(fontSize)px !important;
        }
        h1, h2, h3, h4, h5, h6 {
            font-family: -apple-system-ui-rounded, ui-rounded, 'SF Pro Rounded', -apple-system, system-ui, sans-serif !important;
        }
        h1 {
            font-size: \(fontSize + 6)px !important;
            font-weight: 700 !important;
        }
        h2 {
            font-size: \(fontSize + 4)px !important;
            font-weight: 600 !important;
        }
        h3 {
            font-size: \(fontSize + 2)px !important;
            font-weight: 600 !important;
        }
        """

        return ReaderTheme(
            foreground: isDark ? .white : UIColor(white: 0.15, alpha: 1),
            foreground2: isDark ? UIColor(white: 0.6, alpha: 1) : UIColor(white: 0.45, alpha: 1),
            background: isDark ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.98, alpha: 1),
            background2: isDark ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.92, alpha: 1),
            link: .systemBlue,
            additionalCSS: customCSS
        )
    }
}

// MARK: - Reeeed WebView Wrapper

struct ReeeederWebView: UIViewRepresentable {
    let styledHTML: String
    let baseURL: URL?
    @Binding var fontSize: Double
    let colorScheme: ColorScheme
    let relativeDate: String?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = [.link]

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = colorScheme == .dark ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.98, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.bouncesZoom = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.scrollView.delegate = context.coordinator

        // Store reference for font size updates via manager
        ReaderWebViewManager.shared.currentWebView = webView
        context.coordinator.webView = webView
        print("ReaderWebViewManager: WebView registered")

        // Initial load
        let modifiedHTML = injectFontSize(styledHTML, fontSize: fontSize)
        webView.loadHTMLString(modifiedHTML, baseURL: baseURL)
        context.coordinator.lastFontSize = fontSize

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Update background color
        let newBgColor = colorScheme == .dark ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.98, alpha: 1)
        webView.backgroundColor = newBgColor
        webView.scrollView.backgroundColor = newBgColor

        // Update font size via JavaScript (live update without reload)
        if context.coordinator.lastFontSize != fontSize {
            context.coordinator.lastFontSize = fontSize
            let js = """
            (function() {
                document.body.style.fontSize = '\(fontSize)px';
                document.querySelectorAll('p, li, td, th').forEach(function(el) { el.style.fontSize = '\(fontSize)px'; });
                document.querySelectorAll('h1').forEach(function(el) { el.style.fontSize = '\(fontSize + 6)px'; });
                document.querySelectorAll('h2').forEach(function(el) { el.style.fontSize = '\(fontSize + 4)px'; });
                document.querySelectorAll('h3').forEach(function(el) { el.style.fontSize = '\(fontSize + 2)px'; });
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func injectFontSize(_ html: String, fontSize: Double) -> String {
        // Get the domain for favicon
        let domain = baseURL?.host ?? ""
        let faviconURL = "https://www.google.com/s2/favicons?domain=\(domain)&sz=32"

        // Build date HTML if available
        let dateHTML: String
        if let date = relativeDate {
            dateHTML = "<span class=\"separator\"> · </span><span class=\"date\">\(date)</span>"
        } else {
            dateHTML = ""
        }

        // Inject Apple fonts and font size override into the HTML
        // SF Pro for body, SF Pro Rounded for titles
        // Also style the source badge with favicon
        let fontSizeCSS = """
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
            body {
                font-size: \(fontSize)px !important;
                font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif !important;
                -webkit-font-smoothing: antialiased;
            }
            p, li, td, th {
                font-size: \(fontSize)px !important;
            }
            h1, h2, h3, h4, h5, h6 {
                font-family: -apple-system-ui-rounded, ui-rounded, 'SF Pro Rounded', -apple-system, system-ui, sans-serif !important;
            }
            h1 {
                font-size: \(fontSize + 6)px !important;
                font-weight: 700 !important;
            }
            h2 {
                font-size: \(fontSize + 4)px !important;
                font-weight: 600 !important;
            }
            h3 {
                font-size: \(fontSize + 2)px !important;
                font-weight: 600 !important;
            }
            /* Custom source badge styling */
            .__subtitle {
                display: none !important;
            }
            .__source-badge {
                display: flex !important;
                align-items: center !important;
                gap: 8px !important;
                margin-top: 8px !important;
                margin-bottom: 16px !important;
            }
            .__source-badge img {
                width: 18px !important;
                height: 18px !important;
                border-radius: 4px !important;
                flex-shrink: 0 !important;
            }
            .__source-badge span {
                font-size: 13px !important;
                font-weight: 600 !important;
                text-transform: uppercase !important;
                letter-spacing: 0.5px !important;
                opacity: 0.6 !important;
                color: inherit !important;
                text-decoration: none !important;
            }
            .__source-badge a {
                color: inherit !important;
                text-decoration: none !important;
                pointer-events: none !important;
            }
            .__source-badge .separator {
                opacity: 0.4 !important;
                text-transform: none !important;
            }
            .__source-badge .date {
                text-transform: none !important;
                font-weight: 500 !important;
            }
            /* Hide Reeeed's automatic reader mode footer */
            .__footer, .__reader-footer, [class*="footer"], .reader-footer {
                display: none !important;
            }
            /* Hide any "View original" or "View normal page" buttons */
            a[href*="original"], button[class*="original"],
            a:contains("View"), button:contains("View"),
            div:last-child:has(a[href]) {
                display: none !important;
            }
        </style>
        <script>
            // Remove any footer elements added by the reader library
            document.addEventListener('DOMContentLoaded', function() {
                // Find and remove elements containing "reader mode" or "view normal" text
                var allElements = document.querySelectorAll('*');
                allElements.forEach(function(el) {
                    if (el.innerText && (
                        el.innerText.toLowerCase().includes('reader mode') ||
                        el.innerText.toLowerCase().includes('view normal') ||
                        el.innerText.toLowerCase().includes('view original') ||
                        el.innerText.toLowerCase().includes('automatically converted')
                    )) {
                        // Only hide if it's a small element (not the main content)
                        if (el.innerText.length < 200) {
                            el.style.display = 'none';
                        }
                    }
                });

                // Also check the last few children of body for footer-like content
                var body = document.body;
                if (body) {
                    var children = body.children;
                    for (var i = children.length - 1; i >= Math.max(0, children.length - 3); i--) {
                        var child = children[i];
                        if (child && child.innerText && child.innerText.length < 200 && (
                            child.innerText.toLowerCase().includes('reader') ||
                            child.innerText.toLowerCase().includes('view')
                        )) {
                            child.style.display = 'none';
                        }
                    }
                }
            });
        </script>
        <script>
            document.addEventListener('DOMContentLoaded', function() {
                // Hide the original subtitle
                var subtitle = document.querySelector('.__subtitle');

                // Find the h1 title element
                var title = document.querySelector('#__content h1');
                if (title) {
                    // Find the first significant image (hero image) in the content
                    var content = document.querySelector('#__content');
                    var heroImage = content ? content.querySelector('img, figure, picture') : null;

                    // Move hero image before the title if it exists and isn't already there
                    if (heroImage && title.parentNode) {
                        // Get the figure/picture parent if the image is wrapped
                        var imageContainer = heroImage.closest('figure') || heroImage.closest('picture') || heroImage;
                        // Only move if the image comes after the title in DOM order
                        if (title.compareDocumentPosition(imageContainer) & Node.DOCUMENT_POSITION_FOLLOWING) {
                            title.parentNode.insertBefore(imageContainer, title);
                        }
                    }

                    // Create our custom source badge
                    var sourceBadge = document.createElement('div');
                    sourceBadge.className = '__source-badge';
                    sourceBadge.innerHTML = '<img src="\(faviconURL)" alt="" /><span>\(domain)</span>\(dateHTML)';

                    // Insert source badge right after the title
                    title.parentNode.insertBefore(sourceBadge, title.nextSibling);
                }
            });
        </script>
        """

        // Insert before closing </head> tag if present
        if let headEndRange = html.range(of: "</head>", options: .caseInsensitive) {
            var modifiedHTML = html
            modifiedHTML.insert(contentsOf: fontSizeCSS, at: headEndRange.lowerBound)
            return modifiedHTML
        }

        // Otherwise prepend to the HTML
        return fontSizeCSS + html
    }

    class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate {
        var lastFontSize: Double = 0
        weak var webView: WKWebView?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        // Prevent zooming
        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            scrollView.pinchGestureRecognizer?.isEnabled = false
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return nil
        }
    }
}

// MARK: - Glass Toolbar Button Style

struct GlassToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Animated Gradient Sparkle

struct AnimatedGradientSparkle: View {
    @State private var animateGradient = false

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 28))
            .foregroundStyle(
                LinearGradient(
                    colors: [.purple, .blue, .cyan, .purple],
                    startPoint: animateGradient ? .topLeading : .bottomTrailing,
                    endPoint: animateGradient ? .bottomTrailing : .topLeading
                )
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    animateGradient = true
                }
            }
    }
}

// MARK: - Safari Reader View

struct SafariReaderView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        config.barCollapsingEnabled = true

        let safariVC = SFSafariViewController(url: url, configuration: config)
        safariVC.preferredControlTintColor = .systemBlue
        return safariVC
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }
}

