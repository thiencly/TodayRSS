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
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                if contentMode == .fill {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            } else {
                placeholder()
            }
        }
        .task(id: url?.absoluteString ?? "") { await load() }
    }

    private func load() async {
        guard let url else { return }
        if let img = await ImageDiskCache.shared.image(for: url) {
            await MainActor.run { image = img }
        }
    }
}