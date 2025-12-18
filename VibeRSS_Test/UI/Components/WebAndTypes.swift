//
//  WebAndTypes.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/27/25.
//


// WebAndTypes.swift
// Safari view wrapper and small helper types used across the app.

import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    var entersReaderIfAvailable: Bool = true  // Auto-enter reader mode when available

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = entersReaderIfAvailable
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.dismissButtonStyle = .close
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

struct WebLink: Identifiable {
    let id = UUID()
    let url: URL
    let title: String?
    let date: Date?
    let thumbnailURL: URL?
    let sourceIconURL: URL?
    let sourceTitle: String?

    init(url: URL, title: String? = nil, date: Date? = nil, thumbnailURL: URL? = nil, sourceIconURL: URL? = nil, sourceTitle: String? = nil) {
        self.url = url
        self.title = title
        self.date = date
        self.thumbnailURL = thumbnailURL
        self.sourceIconURL = sourceIconURL
        self.sourceTitle = sourceTitle
    }
}
