// VibeRSS.swift
// SwiftUI RSS reader starter with feed icons + auto-favicon fetch
// iOS 17+ • SwiftUI • async/await • XMLParser (RSS + Atom)

import SwiftUI
import SafariServices

@main
struct VibeRSSApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Register background tasks
        BackgroundSyncManager.shared.registerBackgroundTasks()

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

        // Schedule initial background refresh
        BackgroundSyncManager.shared.scheduleBackgroundRefresh()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Schedule background refresh when entering background
                BackgroundSyncManager.shared.handleEnterBackground()
            case .active:
                // Check if sync is needed when becoming active
                Task {
                    await BackgroundSyncManager.shared.handleBecomeActive()
                }
            default:
                break
            }
        }
    }
}
