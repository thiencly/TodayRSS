//
//  ArticleThumbnailView.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/26/25.
//


// FILE: UI/Components/ArticleThumbnailView.swift
// PURPOSE: Small thumbnail view used in lists
// SAFE TO EDIT: Yes

import SwiftUI

// Global throttle to prevent too many images rendering at once
private actor ThumbnailRenderThrottle {
    static let shared = ThumbnailRenderThrottle()
    private var activeRenders = 0
    private let maxConcurrent = 3  // Only render 3 thumbnails at a time

    func waitForSlot() async {
        while activeRenders >= maxConcurrent {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms between checks
        }
        activeRenders += 1
    }

    func releaseSlot() {
        activeRenders = max(0, activeRenders - 1)
    }
}

struct ArticleThumbnailView: View {
    let url: URL
    @State private var loadedImage: UIImage?

    private let size: CGFloat = 60

    var body: some View {
        // Fixed-size placeholder that renders immediately
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.quaternary)
            .frame(width: size, height: size)
            .overlay {
                if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .task {
                // Check cache synchronously first - no delay needed if cached
                if let cached = ImageDiskCache.cachedImage(for: url),
                   cached.size.width > 0 && cached.size.height > 0 {
                    loadedImage = cached
                    return
                }

                // Small initial delay to let List render
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

                // Wait for a render slot to prevent too many simultaneous renders
                await ThumbnailRenderThrottle.shared.waitForSlot()
                defer { Task { await ThumbnailRenderThrottle.shared.releaseSlot() } }

                // Load from cache/network
                if let img = await ImageDiskCache.shared.image(for: url),
                   img.size.width > 0 && img.size.height > 0 {
                    loadedImage = img
                }
            }
    }
}