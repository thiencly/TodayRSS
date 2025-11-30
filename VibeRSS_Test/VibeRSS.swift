// VibeRSS.swift
// SwiftUI RSS reader starter with feed icons + auto-favicon fetch
// iOS 17+ • SwiftUI • async/await • XMLParser (RSS + Atom)

import SwiftUI
import SafariServices

@main
struct VibeRSSApp: App {
    init() {
        // Initialize cache lookup on background thread (prevents first-tap lag)
        ArticleSummarizer.initializeLookupAsync()

        // Pre-warm SFSafariViewController to avoid first-tap delay
        DispatchQueue.main.async {
            // Create a dummy instance to trigger Safari web content process initialization
            // Use a valid HTTPS URL (SFSafariViewController only supports HTTP/HTTPS)
            let warmupVC = SFSafariViewController(url: URL(string: "https://apple.com")!)
            // Force view loading to fully initialize the process
            _ = warmupVC.view
        }

        // Warm up the on-device summarization model early
        Task {
            await ArticleSummarizer.shared.warmUp()
        }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
