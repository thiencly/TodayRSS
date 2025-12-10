// VibeRSS.swift
// SwiftUI RSS reader starter with feed icons + auto-favicon fetch
// iOS 17+ • SwiftUI • async/await • XMLParser (RSS + Atom)

import SwiftUI
import SafariServices

// Make URL work with fullScreenCover(item:)
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

@main
struct VibeRSSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearanceMode") private var appearanceMode: String = "auto"
    @State private var deepLinkURL: URL?
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

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
                .preferredColorScheme(preferredColorScheme)
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView(isPresented: $showOnboarding)
                }
                .fullScreenCover(item: $deepLinkURL) { url in
                    ReaderSafariView(url: url)
                        .ignoresSafeArea()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            switch newPhase {
            case .background:
                // Schedule background refresh when entering background
                BackgroundSyncManager.shared.handleEnterBackground()
            case .active:
                // Check if sync is needed when becoming active (also fires on initial launch)
                Task {
                    await BackgroundSyncManager.shared.handleBecomeActive()
                }
            default:
                break
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Handle todayrss://read?url=ENCODED_ARTICLE_URL
        guard url.scheme == "todayrss",
              url.host == "read",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let urlParam = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let articleURL = URL(string: urlParam) else {
            return
        }
        deepLinkURL = articleURL
    }
}
