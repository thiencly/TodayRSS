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
    let isRetryingSummary: Bool
    let hasSummaryFailed: Bool
    var onTitleTap: () -> Void
    var onRetryTap: () -> Void

    @State private var dominantColor: Color = Color.black
    @State private var isDarkBackground: Bool = true
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
            let imageHeight = geometry.size.height * 0.8
            let gradientHeight = imageHeight / 3

            ZStack(alignment: .top) {
                // Background
                if article.thumbnailURL != nil {
                    dominantColor.ignoresSafeArea()
                } else {
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

                // Thumbnail image
                if let thumbnailURL = article.thumbnailURL {
                    VStack(spacing: 0) {
                        HighResThumbnailView(url: thumbnailURL, contentMode: .fill) { extractedColor in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                dominantColor = extractedColor
                                isDarkBackground = isColorDark(extractedColor)
                            }
                        }
                        .id(thumbnailURL)
                        .frame(width: geometry.size.width, height: imageHeight)
                        .clipped()

                        Spacer()
                    }

                    // Gradient overlay
                    LinearGradient(
                        stops: [
                            .init(color: dominantColor.opacity(0.01), location: 0),
                            .init(color: dominantColor, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: geometry.size.width, height: gradientHeight)
                    .position(x: geometry.size.width / 2, y: imageHeight - gradientHeight / 2)
                    .allowsHitTesting(false)

                    // Solid color fill below the image (fills remaining 20%)
                    let bottomHeight = geometry.size.height - imageHeight
                    dominantColor
                        .frame(width: geometry.size.width, height: bottomHeight)
                        .position(x: geometry.size.width / 2, y: imageHeight + bottomHeight / 2)
                        .allowsHitTesting(false)
                }

                // Content overlay - text overlaps 10% of image from bottom
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                        .frame(maxHeight: imageHeight * 0.90)

                    // Article info
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
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(primaryTextColor)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticManager.shared.click()
                                onTitleTap()
                            }

                        // Reel summary - also tappable to open reader
                        if let summary = reelSummary, !summary.isEmpty {
                            (Text(Image(systemName: "sparkles")).foregroundColor(sparkleColor) + Text(" ") + Text(summary))
                                .font(.body)
                                .foregroundStyle(summaryTextColor)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    HapticManager.shared.click()
                                    onTitleTap()
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
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 45)
                }
            }
            .clipped()
        }
    }

    // MARK: - Helpers

    private func isColorDark(_ color: Color) -> Bool {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
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

    private let panDuration: Double = 40

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    // Calculate how much the image overflows when filling the container
                    let imageAspect = image.size.width / image.size.height
                    let containerAspect = geometry.size.width / geometry.size.height

                    // When filling, if image is wider than container (relative to height), it overflows horizontally
                    let scaledWidth = imageAspect > containerAspect
                        ? geometry.size.height * imageAspect
                        : geometry.size.width
                    let overflow = max(0, scaledWidth - geometry.size.width)
                    let panAmount = overflow / 2

                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        let elapsed = context.date.timeIntervalSince(startTime)
                        let offset = sin(elapsed * .pi / (panDuration / 2)) * panAmount

                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
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
        startTime = Date()

        if let cachedColor = ImageDiskCache.cachedColor(for: url) {
            onColorExtracted?(Color(cachedColor))
        }

        isLoading = true

        let result = await ImageDiskCache.shared.highResImageWithColor(for: url)

        guard !Task.isCancelled else { return }

        image = result?.image
        if let uiColor = result?.dominantColor {
            onColorExtracted?(Color(uiColor))
        }
        isLoading = false
    }
}

// MARK: - News Reel Glow

struct NewsReelGlow: View {
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
            let wave = sin(seconds * 0.3) * 0.5

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

// MARK: - UIKit Tap Gesture Wrapper

/// A UIKit-based tap gesture that bypasses SwiftUI's gesture system
struct TappableView<Content: View>: UIViewRepresentable {
    let content: Content
    let onTap: () -> Void

    init(onTap: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.onTap = onTap
    }

    func makeUIView(context: Context) -> UIView {
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear

        let containerView = TapContainerView()
        containerView.onTap = onTap
        containerView.backgroundColor = .clear

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        context.coordinator.hostingController = hostingController

        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.hostingController?.rootView = content
        if let containerView = uiView as? TapContainerView {
            containerView.onTap = onTap
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var hostingController: UIHostingController<Content>?
    }
}

/// Container view with UITapGestureRecognizer
private class TapContainerView: UIView {
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.cancelsTouchesInView = false
        addGestureRecognizer(tapGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleTap() {
        onTap?()
    }
}
