// VibeRSS.swift
// SwiftUI RSS reader starter with feed icons + auto-favicon fetch
// iOS 17+ • SwiftUI • async/await • XMLParser (RSS + Atom)

import SwiftUI

@main
struct VibeRSSApp: App {
    init() {
        // Warm up the on-device summarization model early
        Task {
            await ArticleSummarizer.shared.warmUp()
        }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
