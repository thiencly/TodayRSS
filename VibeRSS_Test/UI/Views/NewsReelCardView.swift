//
//  NewsReelCardView.swift
//  VibeRSS_Test
//
//  Individual article card for news reel with widget-style gradient design
//

import SwiftUI

struct NewsReelCardView: View {
    let article: Article
    let reelSummary: String?
    let isLoadingSummary: Bool
    let isRetryingSummary: Bool  // Whether currently retrying after failure
    let hasSummaryFailed: Bool  // Whether all retry attempts exhausted
    let isExpanded: Bool  // Whether showing expanded summary
    let expandedSummary: String  // The streaming/expanded summary text
    let isStreamingSummary: Bool  // Whether currently streaming
    let summaryLength: String  // "short" or "long"
    var onTitleTap: () -> Void  // Opens reader mode
    var onSummaryTap: () -> Void  // Expands/generates summary
    var onCollapseTap: () -> Void  // Collapse back to reel summary
    var onRetryTap: () -> Void  // Retry failed summary generation

    @State private var dominantColor: Color = Color.black
    @State private var isDarkBackground: Bool = true  // Track if background is dark (for text color)
    @State private var sparkleColor: Color = AppleIntelligenceColors.colors.randomElement() ?? .purple

    // Text colors based on background brightness
    private var primaryTextColor: Color {
        isDarkBackground ? .white : Color(white: 0.15)
    }
    private var secondaryTextColor: Color {
        isDarkBackground ? .white.opacity(0.9) : Color(white: 0.2)
    }
    private var tertiaryTextColor: Color {
        isDarkBackground ? .white.opacity(0.6) : Color(white: 0.35)
    }
    private var summaryTextColor: Color {
        isDarkBackground ? .white.opacity(0.85) : Color(white: 0.2)
    }

    // Format relative time
    private var relativeTime: String {
        guard let date = article.pubDate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        GeometryReader { geometry in
            // Slide offset when expanded (for long summaries)
            let slideOffset: CGFloat = isExpanded ? 240 : 0

            let imageHeight = geometry.size.height * 0.8
            let gradientHeight = imageHeight / 3  // 1/3 of image height

            // Calculate available space for expanded summary
            // Base content area (20%) + slide offset - space for source/title and padding
            let availableSummaryHeight: CGFloat = geometry.size.height * 0.20 + slideOffset - 100

            ZStack(alignment: .top) {
                // Background
                if article.thumbnailURL != nil {
                    // Use extracted dominant color for articles with images
                    dominantColor.ignoresSafeArea()
                } else {
                    // Full-screen animated glow for articles without images
                    Color.black.ignoresSafeArea()
                    NewsReelGlow()
                        .ignoresSafeArea()

                    // Large favicon in upper area
                    VStack {
                        Spacer()
                            .frame(height: geometry.size.height * 0.25)
                        if let iconURL = article.sourceIconURL {
                            CachedAsyncImage(url: iconURL, contentMode: .fill, size: CGSize(width: 120, height: 120)) {
                                Image(systemName: "newspaper.fill")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                            .opacity(0.9)
                        } else {
                            Image(systemName: "newspaper.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                        Spacer()
                    }
                }

                // Thumbnail takes up 80% of screen from the top, fills and crops
                // Only show image area if there's a thumbnail
                if let thumbnailURL = article.thumbnailURL {
                    VStack(spacing: 0) {
                        HighResThumbnailView(url: thumbnailURL, contentMode: .fill) { extractedColor in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                dominantColor = extractedColor
                                isDarkBackground = isColorDark(extractedColor)
                            }
                        }
                        .id(thumbnailURL) // Force new view instance for each URL to reset pan animation
                        .frame(width: geometry.size.width, height: imageHeight)
                        .clipped()

                        Spacer()
                    }
                    .offset(y: -slideOffset)

                    // Gradient overlay - only needed for images
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: dominantColor, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: geometry.size.width, height: gradientHeight)
                    .position(x: geometry.size.width / 2, y: imageHeight - gradientHeight / 2 - slideOffset)

                    // Solid color fill below the image - only needed for images
                    dominantColor
                        .frame(width: geometry.size.width, height: geometry.size.height * 0.3 + slideOffset)
                        .position(x: geometry.size.width / 2, y: imageHeight + (geometry.size.height * 0.3 + slideOffset) / 2 - slideOffset)
                }

                // Content overlay - text overlaps 20% of image height
                VStack(spacing: 0) {
                    Spacer()

                    // Article info - raised to overlap into image
                    VStack(alignment: .leading, spacing: 14) {
                        // Source badge with time
                        HStack(spacing: 6) {
                            if let iconURL = article.sourceIconURL {
                                CachedAsyncImage(url: iconURL, contentMode: .fill, size: CGSize(width: 22, height: 22)) {
                                    Image(systemName: "dot.radiowaves.up.forward")
                                        .font(.system(size: 11))
                                        .foregroundStyle(tertiaryTextColor)
                                }
                                .frame(width: 22, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            }

                            if let sourceName = article.sourceTitle {
                                Text(sourceName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(secondaryTextColor)
                            }

                            if !relativeTime.isEmpty {
                                Text("·")
                                    .font(.subheadline)
                                    .foregroundStyle(tertiaryTextColor)
                                Text(relativeTime)
                                    .font(.subheadline)
                                    .foregroundStyle(tertiaryTextColor)
                            }

                            Spacer()
                        }

                        // Article title - tappable to open reader
                        Text(article.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(primaryTextColor)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticManager.shared.click()
                                onTitleTap()
                            }

                        // Summary section
                        if isExpanded {
                            // Expanded summary view - only scrollable if content doesn't fit
                            ExpandedSummaryContent(
                                expandedSummary: expandedSummary,
                                isStreamingSummary: isStreamingSummary,
                                sparkleColor: sparkleColor,
                                isDarkBackground: isDarkBackground,
                                availableHeight: availableSummaryHeight,
                                onTap: {
                                    HapticManager.shared.click()
                                    onCollapseTap()
                                }
                            )
                        } else {
                            // Reel summary - tappable to expand
                            if let summary = reelSummary, !summary.isEmpty {
                                (Text(Image(systemName: "sparkles")).foregroundColor(sparkleColor) + Text(" ") + Text(summary))
                                    .font(.body)
                                    .foregroundStyle(summaryTextColor)
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        HapticManager.shared.click()
                                        onSummaryTap()
                                    }
                            } else if isLoadingSummary || isRetryingSummary {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: primaryTextColor))
                                        .scaleEffect(0.8)
                                    Text(isRetryingSummary ? "Retrying..." : "Generating summary...")
                                        .font(.subheadline)
                                        .foregroundStyle(tertiaryTextColor)
                                }
                            } else if hasSummaryFailed {
                                // Tap to retry button
                                Button {
                                    HapticManager.shared.click()
                                    onRetryTap()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.subheadline)
                                        Text("Tap to retry summary")
                                            .font(.subheadline)
                                    }
                                    .foregroundStyle(sparkleColor)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(sparkleColor.opacity(0.15))
                                    )
                                }
                                .buttonStyle(.plain)
                            } else if !article.summary.isEmpty {
                                Text(stripHTML(article.summary))
                                    .font(.body)
                                    .foregroundStyle(summaryTextColor)
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        HapticManager.shared.click()
                                        onSummaryTap()
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 25)
                    // Raise text to overlap 10% of image
                    .offset(y: -(imageHeight * 0.10))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
        }
    }

    // MARK: - Helpers

    /// Calculate if a color is dark based on luminance
    private func isColorDark(_ color: Color) -> Bool {
        // Convert Color to UIColor to get RGB components
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        // Calculate luminance using standard formula
        // Weights: R=0.299, G=0.587, B=0.114
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue

        // If luminance < 0.5, the color is dark
        return luminance < 0.5
    }

    private func stripHTML(_ html: String) -> String {
        var result = html
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&#8217;", with: "'")
        result = result.replacingOccurrences(of: "&#8220;", with: "\"")
        result = result.replacingOccurrences(of: "&#8221;", with: "\"")
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - High-Resolution Thumbnail View with Color Extraction and Pan Effect

struct HighResThumbnailView: View {
    let url: URL
    var contentMode: ContentMode = .fit
    var onColorExtracted: ((Color) -> Void)?

    @State private var image: UIImage?
    @State private var isLoading: Bool = false
    @State private var startTime: Date = Date()

    // Pan animation settings
    private let panAmount: CGFloat = 30  // How far to pan (points)
    private let panDuration: Double = 12  // Full cycle duration (seconds)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    // Use TimelineView for reliable continuous animation
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        let elapsed = context.date.timeIntervalSince(startTime)
                        // Sine wave oscillation between -panAmount and +panAmount
                        let offset = sin(elapsed * .pi / (panDuration / 2)) * panAmount

                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                            .frame(width: geometry.size.width + panAmount * 2, height: geometry.size.height)
                            .offset(x: offset)
                    }
                } else if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        // Reset start time for this image
        startTime = Date()

        // Check for cached color first
        if let cachedColor = ImageDiskCache.cachedColor(for: url) {
            onColorExtracted?(Color(cachedColor))
        }

        isLoading = true

        // Load high-resolution image for full-screen display
        let result = await ImageDiskCache.shared.highResImageWithColor(for: url)

        guard !Task.isCancelled else { return }

        image = result?.image
        if let uiColor = result?.dominantColor {
            onColorExtracted?(Color(uiColor))
        }
        isLoading = false
    }
}

// MARK: - Expanded Summary Overlay

struct ExpandedSummaryOverlay: View {
    let article: Article
    @Binding var expandedSummary: String
    @Binding var isVisible: Bool
    var summaryStream: AsyncStream<String>?
    var isStreaming: Bool

    @State private var streamTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Summary panel slides up from bottom
            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 16) {
                    // Drag handle
                    HStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 40, height: 5)
                        Spacer()
                    }
                    .padding(.top, 8)

                    // Header
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.headline)
                            .foregroundStyle(AppleIntelligenceColors.colors.randomElement() ?? .purple)
                        Text("Summary")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Article title
                    Text(article.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Divider()

                    // Summary content (scrollable)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if !expandedSummary.isEmpty {
                                Text(expandedSummary)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineSpacing(4)
                            } else if isStreaming {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.8)
                                    Text("Generating summary...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 350)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 8)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            startStreaming()
        }
        .onDisappear {
            streamTask?.cancel()
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.height > 80 {
                        dismiss()
                    }
                }
        )
    }

    private func startStreaming() {
        guard let stream = summaryStream, expandedSummary.isEmpty else { return }

        streamTask = Task {
            for await text in stream {
                await MainActor.run {
                    expandedSummary = text
                }
            }
        }
    }

    private func dismiss() {
        HapticManager.shared.click()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isVisible = false
        }
    }
}

// MARK: - Expanded Summary Content with Conditional Scroll

struct ExpandedSummaryContent: View {
    let expandedSummary: String
    let isStreamingSummary: Bool
    let sparkleColor: Color
    let isDarkBackground: Bool
    let availableHeight: CGFloat
    let onTap: () -> Void

    @State private var contentHeight: CGFloat = 0
    @State private var isScrollable: Bool = false
    @State private var isAtBottom: Bool = false

    // Dynamic text colors based on background
    private var primaryTextColor: Color {
        isDarkBackground ? .white : Color(white: 0.15)
    }
    private var tertiaryTextColor: Color {
        isDarkBackground ? .white.opacity(0.6) : Color(white: 0.35)
    }
    private var summaryTextColor: Color {
        isDarkBackground ? .white.opacity(0.85) : Color(white: 0.2)
    }

    private var summaryTextView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isStreamingSummary && expandedSummary.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: primaryTextColor))
                        .scaleEffect(0.8)
                    Text("Generating summary...")
                        .font(.subheadline)
                        .foregroundStyle(tertiaryTextColor)
                }
            } else {
                (Text(Image(systemName: "sparkles")).foregroundColor(sparkleColor) + Text(" ") + Text(expandedSummary))
                    .font(.body)
                    .foregroundStyle(summaryTextColor)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Actual content display
            if isScrollable {
                ScrollView {
                    summaryTextView
                        .background(
                            GeometryReader { innerGeo in
                                Color.clear
                                    .preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: innerGeo.frame(in: .named("expandedScroll")).maxY
                                    )
                            }
                        )
                }
                .coordinateSpace(name: "expandedScroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
                    // Check if scrolled to bottom (with small tolerance)
                    isAtBottom = maxY <= availableHeight + 10
                }
                .frame(maxHeight: availableHeight, alignment: .top)
            } else {
                summaryTextView
                    .frame(maxHeight: availableHeight, alignment: .top)
            }

            // Chevron indicator - only show if scrollable and not at bottom
            if isScrollable && !isAtBottom {
                HStack {
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(tertiaryTextColor)
                    Spacer()
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .background(
            // Hidden view to measure content height
            summaryTextView
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                contentHeight = geo.size.height
                                isScrollable = contentHeight > availableHeight
                                // Initially not at bottom if scrollable
                                if isScrollable {
                                    isAtBottom = false
                                }
                            }
                            .onChange(of: expandedSummary) { _, _ in
                                DispatchQueue.main.async {
                                    let newHeight = geo.size.height
                                    contentHeight = newHeight
                                    isScrollable = newHeight > availableHeight
                                    // Reset to not at bottom when content changes and is scrollable
                                    if isScrollable {
                                        isAtBottom = false
                                    }
                                }
                            }
                    }
                )
                .hidden()
        )
        .animation(.easeInOut(duration: 0.2), value: isScrollable)
        .animation(.easeInOut(duration: 0.2), value: isAtBottom)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

// Preference key for tracking scroll position
private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - News Reel Glow (same colors as Today Highlights / PriorityNotificationGlow)

struct NewsReelGlow: View {
    // Static cache - randomized once, same as PriorityNotificationGlow
    private static let cachedConfig: GlowConfig = {
        let shuffled = AppleIntelligenceColors.colors.shuffled()
        let offset = Double.random(in: 0..<100)
        return GlowConfig(colors: shuffled, phaseOffset: offset)
    }()

    private struct GlowConfig {
        let colors: [Color]
        let phaseOffset: Double
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate + Self.cachedConfig.phaseOffset

            // Use sine wave for smooth back-and-forth motion (no jump at loop)
            let wave = sin(seconds * 0.3) * 0.5

            // Gradient moves smoothly back and forth
            LinearGradient(
                colors: Self.cachedConfig.colors,
                startPoint: UnitPoint(x: wave - 0.3, y: 0.2),
                endPoint: UnitPoint(x: wave + 0.7, y: 0.8)
            )
            .blur(radius: 50)
            .opacity(0.6)
            .drawingGroup()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

