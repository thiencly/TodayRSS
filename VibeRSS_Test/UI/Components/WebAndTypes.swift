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
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        let vc = SFSafariViewController(url: url, configuration: config)
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

struct WebLink: Identifiable { let id = UUID(); let url: URL }
