//
//  FullBleedThumbnailView.swift
//  VibeRSS_Test
//
//  Full-screen thumbnail view for news reel cards
//

import SwiftUI
import UIKit

/// Full-bleed thumbnail view that fills the entire screen
/// Uses ImageDiskCache for loading and displays a gradient fallback when no image
struct FullBleedThumbnailView: View {
    let url: URL?
    let fallbackGradient: [Color]

    @State private var image: UIImage?
    @State private var loadedURL: URL?
    @State private var isLoading: Bool = false

    init(url: URL?, fallbackGradient: [Color] = [Color(white: 0.15), Color(white: 0.05)]) {
        self.url = url
        self.fallbackGradient = fallbackGradient
    }

    private func isValidImage(_ image: UIImage?) -> Bool {
        guard let image = image else { return false }
        return image.size.width > 0 && image.size.height > 0
    }

    private var cachedImage: UIImage? {
        guard let url else { return nil }
        let cached = ImageDiskCache.cachedImage(for: url)
        return isValidImage(cached) ? cached : nil
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Gradient fallback always shown as base layer
                LinearGradient(
                    colors: fallbackGradient,
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Thumbnail image on top (if available)
                if let displayImage = image ?? cachedImage, isValidImage(displayImage) {
                    Image(uiImage: displayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .onAppear { loadHighResImage() }
        .onChange(of: url) { _, _ in loadHighResImage() }
    }

    private func loadHighResImage() {
        guard let url, url != loadedURL else { return }

        // Check sync cache first
        if let cached = ImageDiskCache.cachedImage(for: url), isValidImage(cached) {
            image = cached
            loadedURL = url
            return
        }

        guard !isLoading else { return }
        isLoading = true

        Task(priority: .userInitiated) {
            // Load full resolution image (not downsampled)
            let loadedImage = await loadFullResolutionImage(from: url)

            await MainActor.run {
                if let img = loadedImage, isValidImage(img) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        image = img
                        loadedURL = url
                    }
                }
                isLoading = false
            }
        }
    }

    /// Load full resolution image for full-screen display
    private func loadFullResolutionImage(from url: URL) async -> UIImage? {
        // First check the disk cache (which may have a downsampled version)
        // For full-bleed we want higher quality, so we'll load fresh if needed
        if let cached = await ImageDiskCache.shared.image(for: url), isValidImage(cached) {
            // The cached version may be downsampled - check if it's adequate for full screen
            // If it's at least 640px wide, it's good enough for full-bleed display
            if cached.size.width >= 640 || cached.size.height >= 640 {
                return cached
            }
        }

        // Load directly for higher quality
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               let image = UIImage(data: data),
               isValidImage(image) {
                return image
            }
        } catch {
            // Fall back to cache even if smaller
            return await ImageDiskCache.shared.image(for: url)
        }

        return nil
    }
}

/// A version that supports preloading the next image
struct PreloadingFullBleedThumbnailView: View {
    let currentURL: URL?
    let nextURL: URL?
    let fallbackGradient: [Color]

    init(currentURL: URL?, nextURL: URL? = nil, fallbackGradient: [Color] = [Color(white: 0.15), Color(white: 0.05)]) {
        self.currentURL = currentURL
        self.nextURL = nextURL
        self.fallbackGradient = fallbackGradient
    }

    var body: some View {
        FullBleedThumbnailView(url: currentURL, fallbackGradient: fallbackGradient)
            .onAppear {
                // Preload next image in background
                if let nextURL {
                    Task(priority: .utility) {
                        _ = await ImageDiskCache.shared.image(for: nextURL)
                    }
                }
            }
    }
}
