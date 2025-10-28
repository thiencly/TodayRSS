//
//  TodayView.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/27/25.
//

//
// TodayView.swift
// Extracted from VibeRSS.swift to keep the main app file focused.
// This view shows a “Today” feed: the latest article per source with a one-line summary.
// Dependencies:
// - FeedStore (EnvironmentObject)
// - FeedService
// - ArticleSummarizer (for cached and streamed summaries)
// - TodayCardView (UI for the card, assumed to exist in the project)
// - UIKit (for UIApplication.shared.open)
//

import SwiftUI
import Foundation
import UIKit

struct TodayView: View {
    // Provided by the app’s environment; contains subscribed feeds, etc.
    @EnvironmentObject private var store: FeedStore

    // A refresh token passed from the parent to trigger reloads
    var refreshID: UUID = UUID()

    // Local UI state
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cards: [TodayCard] = []

    // Service used to fetch items for feeds
    private let service = FeedService()

    // Data model for a single “today” card
    struct TodayCard: Identifiable, Hashable {
        let id = UUID()
        let source: Source
        let latest: Article
        var oneLine: String
    }

    // MARK: - Loading
    @MainActor private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Keep this lightweight: only consider the first few feeds
        let feeds = Array(store.feeds.prefix(5))
        var built: [TodayCard] = []

        await withTaskGroup(of: TodayCard?.self) { group in
            for feed in feeds {
                group.addTask {
                    do {
                        // Fetch items for the feed
                        let items = try await self.service.loadItems(from: feed.url)

                        // Take the newest article (by pubDate)
                        guard let latest = items
                            .sorted(by: { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) })
                            .first else {
                            return nil
                        }

                        // Prefer cached summary to minimize latency; otherwise stream a short one
                        let length: ArticleSummarizer.Length = .quick
                        if let cached = await ArticleSummarizer.shared.cachedSummary(for: latest.link, length: length) {
                            let one = cached
                            return TodayCard(source: feed, latest: latest, oneLine: one)
                        } else {
                            var collected = ""
                            let stream = await ArticleSummarizer.shared.streamSummary(
                                url: latest.link,
                                length: .quick,
                                seedText: latest.summary
                            )
                            for await partial in stream {
                                collected = partial
                            }
                            let one = collected
                            return TodayCard(source: feed, latest: latest, oneLine: one)
                        }
                    } catch {
                        return nil
                    }
                }
            }

            for await result in group {
                if let card = result { built.append(card) }
            }
        }

        // Sort for stable display
        built.sort { $0.source.title.localizedCaseInsensitiveCompare($1.source.title) == .orderedAscending }
        self.cards = built
    }

    // MARK: - View
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: []) {
                ForEach(cards) { card in
                    TodayCardView(card: card)
                        .onTapGesture {
                            // Open article in Safari like elsewhere
                            UIApplication.shared.open(card.latest.link)
                        }
                        .padding(.horizontal, 16)
                }
                if isLoading && cards.isEmpty {
                    ProgressView().padding()
                }
                if let errorMessage, cards.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(errorMessage).multilineTextAlignment(.center)
                    }.padding()
                }
            }
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { Task { await load() } }) {
                    Image(systemName: "arrow.clockwise")
                }.disabled(isLoading)
            }
        }
        // Trigger initial load and respond to parent refresh
        .task(id: refreshID) { await load() }
        .refreshable { await load() }
    }
}

