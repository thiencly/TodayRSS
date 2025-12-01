//
//  CachedAsyncImage.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/26/25.
//


// FILE: UI/Components/CachedAsyncImage.swift
// PURPOSE: SwiftUI image view backed by ImageDiskCache
// SAFE TO EDIT: Yes, used across small components

import SwiftUI
import UIKit

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fit
    var size: CGSize? = nil  // Optional explicit size to prevent layout issues
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: UIImage?
    @State private var loadedURL: URL?  // Track which URL we've loaded

    // Validate image has non-zero dimensions
    private func isValidImage(_ image: UIImage?) -> Bool {
        guard let image = image else { return false }
        return image.size.width > 0 && image.size.height > 0
    }

    // Check sync cache immediately for the current image
    private var cachedImage: UIImage? {
        guard let url else { return nil }
        let cached = ImageDiskCache.cachedImage(for: url)
        return isValidImage(cached) ? cached : nil
    }

    var body: some View {
        Group {
            // Use sync cached image if available, otherwise use async loaded image
            if let displayImage = image ?? cachedImage, isValidImage(displayImage) {
                if contentMode == .fill {
                    Image(uiImage: displayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size?.width, height: size?.height)
                        .clipped()
                } else {
                    Image(uiImage: displayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size?.width, height: size?.height)
                }
            } else {
                placeholder()
                    .frame(width: size?.width, height: size?.height)
            }
        }
        .clipped()  // Prevent rendering outside bounds
        .onAppear { loadIfNeeded() }
        .onChange(of: url) { _, newURL in
            if newURL != loadedURL {
                loadIfNeeded()
            }
        }
    }

    private func loadIfNeeded() {
        guard let url, url != loadedURL else { return }
        // Check sync cache first - if found, no need for async load
        if let cached = ImageDiskCache.cachedImage(for: url), isValidImage(cached) {
            image = cached
            loadedURL = url
            return
        }
        // Fall back to async load
        Task(priority: .low) {
            if let img = await ImageDiskCache.shared.image(for: url), isValidImage(img) {
                await MainActor.run {
                    image = img
                    loadedURL = url
                }
            }
        }
    }
}