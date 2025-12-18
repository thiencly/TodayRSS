//
//  ArticleReaderView.swift
//  VibeRSS_Test
//
//  Custom reader view for displaying article content using Reeeed extraction
//

import SwiftUI
import WebKit
import Reeeed

// MARK: - Article Reader View

struct ArticleReaderView: View {
    let url: URL
    let articleTitle: String?
    let articleDate: Date?

    init(url: URL, articleTitle: String?, articleDate: Date? = nil) {
        self.url = url
        self.articleTitle = articleTitle
        self.articleDate = articleDate
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var extractedContent: Reeeed.FetchAndExtractionResult?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showSettings = false
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
                } else if let content = extractedContent {
                    articleWebView(content)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showSettings.toggle()
                        } label: {
                            Image(systemName: "textformat.size")
                        }

                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                readerSettingsSheet
            }
        }
        .task {
            await loadArticle()
        }
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
            fontSize: fontSize,
            colorScheme: colorScheme,
            relativeDate: relativeDate
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private var readerSettingsSheet: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    Text("Text Size")
                        .font(.roundedHeadline)

                    HStack(spacing: 24) {
                        Button {
                            if fontSize > 14 { fontSize -= 2 }
                        } label: {
                            Image(systemName: "textformat.size.smaller")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(Circle())
                        }

                        Text("\(Int(fontSize))")
                            .font(.title)
                            .fontWeight(.medium)
                            .frame(width: 60)

                        Button {
                            if fontSize < 28 { fontSize += 2 }
                        } label: {
                            Image(systemName: "textformat.size.larger")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                }

                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showSettings = false
                    }
                }
            }
            .presentationDetents([.height(200)])
        }
    }

    // MARK: - Data Loading

    private func loadArticle() async {
        isLoading = true
        error = nil

        do {
            // Create theme based on current color scheme
            let theme = createTheme()

            // Use Reeeed to extract and style content
            let result = try await Reeeed.fetchAndExtractContent(fromURL: url, theme: theme)

            await MainActor.run {
                self.extractedContent = result
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
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
    let fontSize: Double
    let colorScheme: ColorScheme
    let relativeDate: String?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = [.link]

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = colorScheme == .dark ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.98, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.navigationDelegate = context.coordinator

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Inject custom font size into the styled HTML
        let modifiedHTML = injectFontSize(styledHTML, fontSize: fontSize)
        webView.loadHTMLString(modifiedHTML, baseURL: baseURL)
        webView.backgroundColor = colorScheme == .dark ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.98, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
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
            }
            .__source-badge .separator {
                opacity: 0.4 !important;
                text-transform: none !important;
            }
            .__source-badge .date {
                text-transform: none !important;
                font-weight: 500 !important;
            }
        </style>
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

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
