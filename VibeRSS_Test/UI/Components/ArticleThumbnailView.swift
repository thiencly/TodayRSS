// FILE: UI/Components/ArticleThumbnailView.swift
// PURPOSE: Small thumbnail view used in lists
// SAFE TO EDIT: Yes

import SwiftUI

struct ArticleThumbnailView: View {
    let url: URL
    var body: some View {
        CachedAsyncImage(url: url, contentMode: .fill) {
            Rectangle().fill(.quaternary)
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}