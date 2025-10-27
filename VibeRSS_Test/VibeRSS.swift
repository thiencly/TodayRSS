// VibeRSS.swift
// SwiftUI RSS reader starter with feed icons + auto-favicon fetch
// iOS 17+ • SwiftUI • async/await • XMLParser (RSS + Atom)

import SwiftUI
import Combine
import Foundation
import SafariServices
import UIKit
import CryptoKit
import UniformTypeIdentifiers
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Shared Siri-like Gradient & Glow








// MARK: - Models



#if canImport(FoundationModels)
@Generable(description: "A concise inline summary for streaming")
struct InlineSummary {
    @Guide(description: "The concise summary text")
    var text: String
}
#endif

// MARK: - Terminology aliases


// MARK: - Persistence (simple)


// MARK: - Errors


// MARK: - Networking & Parsing


// MARK: - XML Parsers




// MARK: - Date formats & helpers




// MARK: - ViewModels
@MainActor
final class ItemsViewModel: ObservableObject {
    @Published var items: [Article] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = FeedService()

    func load(for source: Source) async {
        isLoading = true; errorMessage = nil
        do {
            var result = try await service.loadItems(from: source.url)
            for i in result.indices {
                result[i].sourceID = source.id
                result[i].sourceTitle = source.title
                result[i].sourceIconURL = source.iconURL
            }
            guard let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()) else {
                // If date math fails, keep existing items order without filtering
                items = result.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
                isLoading = false
                return
            }
            // Updated filter logic for pubDate nil items kept
            result = result.filter { item in
                if let d = item.pubDate { return d >= cutoff } else { return true }
            }
            items = result.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Folder aggregated items VM
@MainActor
final class FolderItemsViewModel: ObservableObject {
    @Published var items: [Article] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = FeedService()

    func load(for folder: Folder, feeds: [Feed]) async {
        isLoading = true; errorMessage = nil
        let sources = feeds.filter { $0.folderID == folder.id }
        var all: [Article] = []
        await withTaskGroup(of: [FeedItem].self) { group in
            for src in sources {
                group.addTask {
                    do {
                        var r = try await self.service.loadItems(from: src.url)
                        for i in r.indices {
                            r[i].sourceID = src.id
                            r[i].sourceTitle = src.title
                            r[i].sourceIconURL = src.iconURL
                        }
                        return r
                    } catch { return [] }
                }
            }
            for await result in group {
                all.append(contentsOf: result)
            }
        }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()) else {
            // If date math fails, sort without filtering
            items = all.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            isLoading = false
            return
        }
        // Updated filter logic for pubDate nil items kept
        let filtered = all.filter { if let d = $0.pubDate { return d >= cutoff } else { return true } }
        items = filtered.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        isLoading = false
    }

    func loadAll(feeds: [Feed]) async {
        isLoading = true; errorMessage = nil
        let sources = feeds
        var all: [Article] = []
        await withTaskGroup(of: [FeedItem].self) { group in
            for src in sources {
                group.addTask {
                    do {
                        var r = try await self.service.loadItems(from: src.url)
                        for i in r.indices {
                            r[i].sourceID = src.id
                            r[i].sourceTitle = src.title
                            r[i].sourceIconURL = src.iconURL
                        }
                        return r
                    } catch { return [] }
                }
            }
            for await result in group {
                all.append(contentsOf: result)
            }
        }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()) else {
            // If date math fails, sort without filtering
            items = all.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            isLoading = false
            return
        }
        // Updated filter logic for pubDate nil items kept
        let filtered = all.filter { if let d = $0.pubDate { return d >= cutoff } else { return true } }
        items = filtered.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        isLoading = false
    }
}

// MARK: - Favicon service (auto fetch)


// MARK: - Image Disk Cache + Cached Image View






// REPLACED RainbowGlowText with subtle option




// We will fix scaleEffect in SummarizeButton below instead, removing here





// Unified SummaryControl (replaces separate pill + badge)


// REPLACE SpinningSmokeyGlow with TimelineView-driven rotation and stronger smoke


// REPLACE SummaryControl with simpler SummarizeButton (always shows Summarize label)







// Inserted CollapsibleText view before FeedDetailView
struct CollapsibleText: View {
    let text: String
    let isExpanded: Bool
    private let collapsedLineCount: Int = 3

    var body: some View {
        Group {
            if isExpanded {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
                    .contentTransition(.opacity)
            } else {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(collapsedLineCount)
                    .layoutPriority(1)
                    .contentTransition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: isExpanded)
    }
}

// Modified struct FeedDetailView with refreshID property
struct FeedDetailView: View {
    let source: Source
    var refreshID: UUID = UUID()
    @StateObject private var vm = ItemsViewModel()
    @State private var webLink: WebLink?
    @State private var summarizingID: UUID?
    @State private var inlineSummaries: [UUID: String] = [:]
    @State private var expandedSummaries: Set<UUID> = []
    @State private var summaryErrors: Set<UUID> = []
    @State private var hasCachedText: Set<UUID> = [] // <-- Inserted here
    
    // Removed @State private var measuredSummaryHeights: [UUID: CGFloat] = [:]

    @AppStorage("summaryLength") private var summaryLengthRaw: String = "short"
    @State private var aiSummarized: Set<UUID> = []
    @State private var currentDay: Date? = nil
    @State private var suppressNextRowTap = false

    var body: some View {
        Group {
            if vm.isLoading && vm.items.isEmpty {
                ProgressView().controlSize(.large)
            } else if let error = vm.errorMessage, vm.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).multilineTextAlignment(.center)
                    Button("Retry") { Task { await vm.load(for: source) } }
                }.padding()
            } else {
                List(vm.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    webLink = WebLink(url: item.link)
                                }

                            Group {
                                let isError = summaryErrors.contains(item.id)
                                let aiSummary = inlineSummaries[item.id]

                                // Modified SummarizeButton per instruction wrapped in HStack with indicator
                                HStack(spacing: 6) {
                                    SummarizeButton(
                                        state: { () -> SummarizeButton.ButtonState in
                                            if summarizingID == item.id {
                                                return .generating
                                            }
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
                                            let hasCached = (aiSummary != nil) || ArticleSummarizer.hasCachedSummary(url: item.link, length: length)
                                            if hasCached {
                                                return .hasSummary(isExpanded: expandedSummaries.contains(item.id))
                                            } else {
                                                return .none
                                            }
                                        }()
                                    ) {
                                        // Toggle expand/collapse if summary exists; otherwise start summarization
                                        suppressNextRowTap = true
                                        let hasSummary = (aiSummary != nil)
                                        if hasSummary {
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
                                            if expandedSummaries.contains(item.id) {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    expandedSummaries.remove(item.id)
                                                }
                                                Task { await ArticleSummarizer.shared.setExpanded(false, url: item.link, length: length) }
                                            } else {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    expandedSummaries.insert(item.id)
                                                }
                                                Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
                                            }
                                        } else if summarizingID != item.id {
                                            Task { await summarize(item) }
                                        }
                                    }
                                    .disabled(isError)

                                    // Tiny indicator when readable text is cached for this article
                                    if hasCachedText.contains(item.id) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                            .accessibilityLabel("Cached text available")
                                    }
                                }

                                // Stable summary container prevents title jump by reserving height
                                ZStack(alignment: .topLeading) {
                                    if let aiSummary {
                                        CollapsibleText(text: aiSummary, isExpanded: expandedSummaries.contains(item.id))
                                    } else if isError {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                            Text("Summarization unavailable on this device.")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                // Removed .animation(.snappy(duration: 0.25), value: expandedSummaries.contains(item.id))
                            }

                            HStack(alignment: .center, spacing: 6) {
                                SourceBadge(iconURL: item.sourceIconURL ?? source.iconURL, name: item.sourceTitle ?? source.title)
                                if let date = item.pubDate {
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(date, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        Spacer(minLength: 12)
                        if let thumb = item.thumbnailURL {
                            ArticleThumbnailView(url: thumb)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    webLink = WebLink(url: item.link)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DayAnchorReporter(date: item.pubDate, coordinateSpaceName: "FeedListScroll"))
                    .id(item.id)
                    .transaction { $0.disablesAnimations = false }
                }
                .listStyle(.plain)
                .transaction { $0.animation = nil }
                .refreshable { await vm.load(for: source) }
                .coordinateSpace(name: "FeedListScroll")
                .task(id: vm.items.map { $0.id }) { preloadSummaries(for: vm.items) }
                .onChange(of: summaryLengthRaw) { _, _ in }
                .onPreferenceChange(DayAnchorsKey.self) { anchors in
                    guard !anchors.isEmpty else {
                        currentDay = nil
                        return
                    }
                    let sorted = anchors.sorted { a, b in
                        let aScore = (a.minY >= 0) ? a.minY : (100000 + abs(a.minY))
                        let bScore = (b.minY >= 0) ? b.minY : (100000 + abs(b.minY))
                        return aScore < bScore
                    }
                    let topDay = sorted.first?.dayStart
                    if currentDay != topDay {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            currentDay = topDay
                        }
                    }
                }
                .safeAreaInset(edge: .top) {
                    if let d = currentDay {
                        HStack {
                            FloatingDayChip(date: d)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 0)
                        .padding(.leading, 16)
                        .padding(.trailing, 16)
                        .padding(.bottom, 6)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingRefreshButton(isLoading: vm.isLoading) {
                Task { await vm.load(for: source) }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 24)
        }
        .task(id: refreshID) { await vm.load(for: source) }
        .navigationTitle(source.title)
        .sheet(item: $webLink) { w in
            SafariView(url: w.url).ignoresSafeArea()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("Summary Length") {
                        Button {
                            summaryLengthRaw = "short"
                        } label: {
                            HStack {
                                Text("Short")
                                if summaryLengthRaw == "short" { Image(systemName: "checkmark") }
                            }
                        }
                        Button {
                            summaryLengthRaw = "long"
                        } label: {
                            HStack {
                                Text("Long")
                                if summaryLengthRaw == "long" { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    Button("Clear Summaries", role: .destructive) {
                        inlineSummaries.removeAll()
                        aiSummarized.removeAll()
                        expandedSummaries.removeAll()
                        summaryErrors.removeAll()
                        Task { await ArticleSummarizer.shared.clearCache() }
                    }
                    Button("Clear Article Text Cache", role: .destructive) {
                        Task { await ArticleTextCache.shared.clear() }
                    }
                } label: {
                    Image(systemName: "sparkles")
                }
            }
        }
    }

    private func preloadSummaries(for items: [Article]) {
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
        Task { @MainActor in
            var updated = inlineSummaries
            var expanded = expandedSummaries
            var cachedFlags = hasCachedText // <-- Added

            for item in items {
                if updated[item.id] == nil, let cached = await ArticleSummarizer.shared.cachedSummary(for: item.link, length: length) {
                    updated[item.id] = cached
                }
                // Restore expansion state from persisted store (default collapsed)
                if await ArticleSummarizer.shared.isExpanded(url: item.link, length: length) {
                    expanded.insert(item.id)
                } else {
                    expanded.remove(item.id)
                }
                // Update cached text indicator
                if await ArticleTextCache.shared.cachedText(for: item.link) != nil {
                    cachedFlags.insert(item.id)
                } else {
                    cachedFlags.remove(item.id)
                }
            }
            inlineSummaries = updated
            expandedSummaries = expanded
            hasCachedText = cachedFlags // <-- Added
        }
    }

    @MainActor private func summarize(_ item: Article) async {
        summaryErrors.remove(item.id)
        summarizingID = item.id
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short

        if !expandedSummaries.contains(item.id) {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedSummaries.insert(item.id)
            }
            Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
        }

        var sawAny = false

        let stream = await ArticleSummarizer.shared.streamSummary(url: item.link, length: length, seedText: item.summary)
        for await partial in stream {
            sawAny = true
            inlineSummaries[item.id] = partial
            summaryErrors.remove(item.id)
            aiSummarized.insert(item.id)
        }
        if !sawAny {
            summaryErrors.insert(item.id)
        }
        summarizingID = nil
    }
}

// Modified struct FolderDetailView with refreshID property
struct FolderDetailView: View {
    let folder: Folder
    var refreshID: UUID = UUID()
    @EnvironmentObject private var store: FeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteFolder = false
    @StateObject private var vm = FolderItemsViewModel()
    @State private var webLink: WebLink?
    @State private var summarizingID: UUID?
    @State private var inlineSummaries: [UUID: String] = [:]
    @State private var expandedSummaries: Set<UUID> = []
    @State private var summaryErrors: Set<UUID> = []
    @State private var hasCachedText: Set<UUID> = [] // <-- Inserted here
    
    // Removed @State private var measuredSummaryHeights: [UUID: CGFloat] = [:]

    @AppStorage("summaryLength") private var summaryLengthRaw: String = "short"
    @State private var aiSummarized: Set<UUID> = []
    @State private var currentDay: Date? = nil
    @State private var suppressNextRowTap = false

    var body: some View {
        Group {
            if vm.isLoading && vm.items.isEmpty {
                ProgressView().controlSize(.large)
            } else if let error = vm.errorMessage, vm.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).multilineTextAlignment(.center)
                    Button("Retry") { Task { await vm.load(for: folder, feeds: store.feeds) } }
                }.padding()
            } else {
                List(vm.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    webLink = WebLink(url: item.link)
                                }

                            Group {
                                let isError = summaryErrors.contains(item.id)
                                let aiSummary = inlineSummaries[item.id]

                                // Modified SummarizeButton per instruction wrapped in HStack with indicator
                                HStack(spacing: 6) {
                                    SummarizeButton(
                                        state: { () -> SummarizeButton.ButtonState in
                                            if summarizingID == item.id {
                                                return .generating
                                            }
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
                                            let hasCached = (aiSummary != nil) || ArticleSummarizer.hasCachedSummary(url: item.link, length: length)
                                            if hasCached {
                                                return .hasSummary(isExpanded: expandedSummaries.contains(item.id))
                                            } else {
                                                return .none
                                            }
                                        }()
                                    ) {
                                        // Toggle expand/collapse if summary exists; otherwise start summarization
                                        suppressNextRowTap = true
                                        let hasSummary = (aiSummary != nil)
                                        if hasSummary {
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
                                            if expandedSummaries.contains(item.id) {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    expandedSummaries.remove(item.id)
                                                }
                                                Task { await ArticleSummarizer.shared.setExpanded(false, url: item.link, length: length) }
                                            } else {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    expandedSummaries.insert(item.id)
                                                }
                                                Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
                                            }
                                        } else if summarizingID != item.id {
                                            Task { await summarize(item) }
                                        }
                                    }
                                    .disabled(isError)

                                    // Tiny indicator when readable text is cached for this article
                                    if hasCachedText.contains(item.id) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                            .accessibilityLabel("Cached text available")
                                    }
                                }

                                // Stable summary container prevents title jump by reserving height
                                ZStack(alignment: .topLeading) {
                                    if let aiSummary {
                                        CollapsibleText(text: aiSummary, isExpanded: expandedSummaries.contains(item.id))
                                    } else if isError {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                            Text("Summarization unavailable on this device.")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                // Removed .animation(.snappy(duration: 0.25), value: expandedSummaries.contains(item.id))
                            }

                            HStack(alignment: .center, spacing: 6) {
                                SourceBadge(iconURL: item.sourceIconURL, name: item.sourceTitle ?? "Source")
                                if let date = item.pubDate {
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(date, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        Spacer(minLength: 12)
                        if let thumb = item.thumbnailURL {
                            ArticleThumbnailView(url: thumb)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    webLink = WebLink(url: item.link)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DayAnchorReporter(date: item.pubDate, coordinateSpaceName: "FolderListScroll"))
                    .id(item.id)
                    .transaction { $0.disablesAnimations = false }
                }
                .listStyle(.plain)
                .transaction { $0.animation = nil }
                .refreshable { await vm.load(for: folder, feeds: store.feeds) }
                .coordinateSpace(name: "FolderListScroll")
                .task(id: vm.items.map { $0.id }) { preloadSummaries(for: vm.items) }
                .onChange(of: summaryLengthRaw) { _, _ in }
                .onPreferenceChange(DayAnchorsKey.self) { anchors in
                    guard !anchors.isEmpty else {
                        currentDay = nil
                        return
                    }
                    let sorted = anchors.sorted { a, b in
                        let aScore = (a.minY >= 0) ? a.minY : (100000 + abs(a.minY))
                        let bScore = (b.minY >= 0) ? b.minY : (100000 + abs(b.minY))
                        return aScore < bScore
                    }
                    let topDay = sorted.first?.dayStart
                    if currentDay != topDay {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            currentDay = topDay
                        }
                    }
                }
                .safeAreaInset(edge: .top) {
                    if let d = currentDay {
                        HStack {
                            FloatingDayChip(date: d)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 0)
                        .padding(.leading, 16)
                        .padding(.trailing, 16)
                        .padding(.bottom, 6)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingRefreshButton(isLoading: vm.isLoading) {
                Task { await vm.load(for: folder, feeds: store.feeds) }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 24)
        }
        .task(id: refreshID) { await vm.load(for: folder, feeds: store.feeds) }
        .navigationTitle(folder.name)
        .sheet(item: $webLink) { w in
            SafariView(url: w.url).ignoresSafeArea()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) { showingDeleteFolder = true } label: { Image(systemName: "trash") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("Summary Length") {
                        Button {
                            summaryLengthRaw = "short"
                        } label: {
                            HStack {
                                Text("Short")
                                if summaryLengthRaw == "short" { Image(systemName: "checkmark") }
                            }
                        }
                        Button {
                            summaryLengthRaw = "long"
                        } label: {
                            HStack {
                                Text("Long")
                                if summaryLengthRaw == "long" { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    Button("Clear Summaries", role: .destructive) {
                        inlineSummaries.removeAll()
                        aiSummarized.removeAll()
                        expandedSummaries.removeAll()
                        summaryErrors.removeAll()
                        Task { await ArticleSummarizer.shared.clearCache() }
                    }
                    Button("Clear Article Text Cache", role: .destructive) {
                        Task { await ArticleTextCache.shared.clear() }
                    }
                } label: {
                    Image(systemName: "sparkles")
                }
            }
        }
        .alert("Delete Folder?", isPresented: $showingDeleteFolder) {
            Button("Delete", role: .destructive) {
                store.removeFolder(folder)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All sources will remain subscribed but will be removed from this folder.")
        }
    }

    private func preloadSummaries(for items: [Article]) {
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
        Task { @MainActor in
            var updated = inlineSummaries
            var expanded = expandedSummaries
            var cachedFlags = hasCachedText // <-- Added

            for item in items {
                if updated[item.id] == nil, let cached = await ArticleSummarizer.shared.cachedSummary(for: item.link, length: length) {
                    updated[item.id] = cached
                }
                // Restore expansion state from persisted store (default collapsed)
                if await ArticleSummarizer.shared.isExpanded(url: item.link, length: length) {
                    expanded.insert(item.id)
                } else {
                    expanded.remove(item.id)
                }
                // Update cached text indicator
                if await ArticleTextCache.shared.cachedText(for: item.link) != nil {
                    cachedFlags.insert(item.id)
                } else {
                    cachedFlags.remove(item.id)
                }
            }
            inlineSummaries = updated
            expandedSummaries = expanded
            hasCachedText = cachedFlags // <-- Added
        }
    }

    @MainActor private func summarize(_ item: Article) async {
        summaryErrors.remove(item.id)
        summarizingID = item.id
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short

        if !expandedSummaries.contains(item.id) {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedSummaries.insert(item.id)
            }
            Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
        }

        var sawAny = false

        let stream = await ArticleSummarizer.shared.streamSummary(url: item.link, length: length, seedText: item.summary)
        for await partial in stream {
            sawAny = true
            inlineSummaries[item.id] = partial
            summaryErrors.remove(item.id)
            aiSummarized.insert(item.id)
        }
        if !sawAny {
            summaryErrors.insert(item.id)
        }
        summarizingID = nil
    }
}

// Modified struct AllArticlesView with refreshID property
struct AllArticlesView: View {
    @EnvironmentObject private var store: FeedStore
    var refreshID: UUID = UUID()
    @StateObject private var vm = FolderItemsViewModel()
    @State private var webLink: WebLink?
    @State private var summarizingID: UUID?
    @State private var inlineSummaries: [UUID: String] = [:]
    @State private var expandedSummaries: Set<UUID> = []
    @State private var summaryErrors: Set<UUID> = []
    @State private var hasCachedText: Set<UUID> = [] // <-- Inserted here
    
    // Removed @State private var measuredSummaryHeights: [UUID: CGFloat] = [:]

    @AppStorage("summaryLength") private var summaryLengthRaw: String = "short"
    @State private var aiSummarized: Set<UUID> = []
    @State private var currentDay: Date? = nil
    @State private var suppressNextRowTap = false

    var body: some View {
        Group {
            if vm.isLoading && vm.items.isEmpty {
                ProgressView().controlSize(.large)
            } else if let error = vm.errorMessage, vm.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).multilineTextAlignment(.center)
                    Button("Retry") { Task { await vm.loadAll(feeds: store.feeds) } }
                }.padding()
            } else {
                List(vm.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    webLink = WebLink(url: item.link)
                                }

                            Group {
                                let isError = summaryErrors.contains(item.id)
                                let aiSummary = inlineSummaries[item.id]

                                // Modified SummarizeButton per instruction wrapped in HStack with indicator
                                HStack(spacing: 6) {
                                    SummarizeButton(
                                        state: { () -> SummarizeButton.ButtonState in
                                            if summarizingID == item.id {
                                                return .generating
                                            }
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
                                            let hasCached = (aiSummary != nil) || ArticleSummarizer.hasCachedSummary(url: item.link, length: length)
                                            if hasCached {
                                                return .hasSummary(isExpanded: expandedSummaries.contains(item.id))
                                            } else {
                                                return .none
                                            }
                                        }()
                                    ) {
                                        // Toggle expand/collapse if summary exists; otherwise start summarization
                                        suppressNextRowTap = true
                                        let hasSummary = (aiSummary != nil)
                                        if hasSummary {
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
                                            if expandedSummaries.contains(item.id) {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    expandedSummaries.remove(item.id)
                                                }
                                                Task { await ArticleSummarizer.shared.setExpanded(false, url: item.link, length: length) }
                                            } else {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    expandedSummaries.insert(item.id)
                                                }
                                                Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
                                            }
                                        } else if summarizingID != item.id {
                                            Task { await summarize(item) }
                                        }
                                    }
                                    .disabled(isError)

                                    // Tiny indicator when readable text is cached for this article
                                    if hasCachedText.contains(item.id) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                            .accessibilityLabel("Cached text available")
                                    }
                                }

                                // Stable summary container prevents title jump by reserving height
                                ZStack(alignment: .topLeading) {
                                    if let aiSummary {
                                        CollapsibleText(text: aiSummary, isExpanded: expandedSummaries.contains(item.id))
                                    } else if isError {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                            Text("Summarization unavailable on this device.")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                // Removed .animation(.snappy(duration: 0.25), value: expandedSummaries.contains(item.id))
                            }

                            HStack(alignment: .center, spacing: 6) {
                                SourceBadge(iconURL: item.sourceIconURL, name: item.sourceTitle ?? "Source")
                                if let date = item.pubDate {
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(date, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        Spacer(minLength: 12)
                        if let thumb = item.thumbnailURL {
                            ArticleThumbnailView(url: thumb)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    webLink = WebLink(url: item.link)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DayAnchorReporter(date: item.pubDate, coordinateSpaceName: "AllListScroll"))
                    .id(item.id)
                    .transaction { $0.disablesAnimations = false }
                }
                .listStyle(.plain)
                .transaction { $0.animation = nil }
                .refreshable { await vm.loadAll(feeds: store.feeds) }
                .coordinateSpace(name: "AllListScroll")
                .task(id: vm.items.map { $0.id }) { preloadSummaries(for: vm.items) }
                .onChange(of: summaryLengthRaw) { _, _ in }
                .onPreferenceChange(DayAnchorsKey.self) { anchors in
                    guard !anchors.isEmpty else {
                        currentDay = nil
                        return
                    }
                    let sorted = anchors.sorted { a, b in
                        let aScore = (a.minY >= 0) ? a.minY : (100000 + abs(a.minY))
                        let bScore = (b.minY >= 0) ? b.minY : (100000 + abs(b.minY))
                        return aScore < bScore
                    }
                    let topDay = sorted.first?.dayStart
                    if currentDay != topDay {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            currentDay = topDay
                        }
                    }
                }
                .safeAreaInset(edge: .top) {
                    if let d = currentDay {
                        HStack {
                            FloatingDayChip(date: d)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 0)
                        .padding(.leading, 16)
                        .padding(.trailing, 16)
                        .padding(.bottom, 6)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingRefreshButton(isLoading: vm.isLoading) {
                Task { await vm.loadAll(feeds: store.feeds) }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 24)
        }
        .task(id: refreshID) { await vm.loadAll(feeds: store.feeds) }
        .navigationTitle("All Articles")
        .sheet(item: $webLink) { w in
            SafariView(url: w.url).ignoresSafeArea()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("Summary Length") {
                        Button {
                            summaryLengthRaw = "short"
                        } label: {
                            HStack {
                                Text("Short")
                                if summaryLengthRaw == "short" { Image(systemName: "checkmark") }
                            }
                        }
                        Button {
                            summaryLengthRaw = "long"
                        } label: {
                            HStack {
                                Text("Long")
                                if summaryLengthRaw == "long" { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    Button("Clear Summaries", role: .destructive) {
                        inlineSummaries.removeAll()
                        aiSummarized.removeAll()
                        expandedSummaries.removeAll()
                        summaryErrors.removeAll()
                        Task { await ArticleSummarizer.shared.clearCache() }
                    }
                    Button("Clear Article Text Cache", role: .destructive) {
                        Task { await ArticleTextCache.shared.clear() }
                    }
                } label: {
                    Image(systemName: "sparkles")
                }
            }
        }
    }

    private func preloadSummaries(for items: [Article]) {
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
        Task { @MainActor in
            var updated = inlineSummaries
            var expanded = expandedSummaries
            var cachedFlags = hasCachedText // <-- Added

            for item in items {
                if updated[item.id] == nil, let cached = await ArticleSummarizer.shared.cachedSummary(for: item.link, length: length) {
                    updated[item.id] = cached
                }
                // Restore expansion state from persisted store (default collapsed)
                if await ArticleSummarizer.shared.isExpanded(url: item.link, length: length) {
                    expanded.insert(item.id)
                } else {
                    expanded.remove(item.id)
                }
                // Update cached text indicator
                if await ArticleTextCache.shared.cachedText(for: item.link) != nil {
                    cachedFlags.insert(item.id)
                } else {
                    cachedFlags.remove(item.id)
                }
            }
            inlineSummaries = updated
            expandedSummaries = expanded
            hasCachedText = cachedFlags // <-- Added
        }
    }

    @MainActor private func summarize(_ item: Article) async {
        summaryErrors.remove(item.id)
        summarizingID = item.id
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short

        if !expandedSummaries.contains(item.id) {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedSummaries.insert(item.id)
            }
            Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
        }

        var sawAny = false

        let stream = await ArticleSummarizer.shared.streamSummary(url: item.link, length: length, seedText: item.summary)
        for await partial in stream {
            sawAny = true
            inlineSummaries[item.id] = partial
            summaryErrors.remove(item.id)
            aiSummarized.insert(item.id)
        }
        if !sawAny {
            summaryErrors.insert(item.id)
        }
        summarizingID = nil
    }
}

// MARK: - Today View (latest per source with 1-line summaries)
struct TodayView: View {
    @EnvironmentObject private var store: FeedStore
    var refreshID: UUID = UUID()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cards: [TodayCard] = []

    private let service = FeedService()

    struct TodayCard: Identifiable, Hashable {
        let id = UUID()
        let source: Source
        let latest: Article
        var oneLine: String
    }

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
        .task(id: refreshID) { await load() }
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        guard !isLoading else { return }
        isLoading = true; errorMessage = nil
        let feeds = store.feeds
        var built: [TodayCard] = []
        await withTaskGroup(of: TodayCard?.self) { group in
            for feed in feeds {
                group.addTask {
                    do {
                        let items = try await self.service.loadItems(from: feed.url)
                        guard let latest = items.sorted(by: { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }).first else {
                            return nil
                        }
                        // Try cached summary first; otherwise stream a quick short one and take first line
                        let length: ArticleSummarizer.Length = .short
                        if let cached = await ArticleSummarizer.shared.cachedSummary(for: latest.link, length: length) {
                            let one = Self.firstSentence(from: cached)
                            return TodayCard(source: feed, latest: latest, oneLine: one)
                        } else {
                            // Attempt fast primer summary synchronously by consuming initial stream tokens
                            var collected = ""
                            let stream = await ArticleSummarizer.shared.streamSummary(url: latest.link, length: .short, seedText: latest.summary)
                            var tokenCount = 0
                            for await partial in stream {
                                collected = partial
                                tokenCount += 1
                                if tokenCount >= 40 { // small budget; we only need a line
                                    break
                                }
                            }
                            let one = Self.firstSentence(from: collected)
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
        // Stable order: by source title
        built.sort { $0.source.title.localizedCaseInsensitiveCompare($1.source.title) == .orderedAscending }
        cards = built
        isLoading = false
    }

    private static func firstSentence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // Take up to the first period or 100 characters as a fallback
        if let dot = trimmed.firstIndex(of: ".") {
            let first = String(trimmed[..<trimmed.index(after: dot)])
            return String(first.prefix(140))
        }
        return String(trimmed.prefix(140))
    }
}



private struct SidebarHeroCardView: View {
    struct Entry: Identifiable, Hashable, Codable {
        let id = UUID()
        let source: Source
        let title: String
        let oneLine: String
        let link: URL
    }

    let entries: [Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RainbowGlowSymbol(systemName: "sparkles", font: .caption, subtle: true)
                Text("Today Highlights")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }

            ForEach(entries.prefix(5)) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        FeedIconView(iconURL: entry.source.iconURL)
                            .frame(width: 20, height: 20)
                        Text(entry.source.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    Text(entry.oneLine.isEmpty ? entry.title : entry.oneLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .contentShape(Rectangle())
                .onTapGesture { UIApplication.shared.open(entry.link) }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                .blendMode(.overlay)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Add Source UI (auto-favicon)
struct AddFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FeedStore
    @State private var title: String = ""
    @State private var urlString: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var onAdd: (Source) -> Void
    private let faviconService = FaviconService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title (optional)", text: $title)
                    TextField("Source URL (https://…)", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Add Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: add) {
                        if isSaving { ProgressView() } else { Text("Add") }
                    }.disabled(!isValidURL || isSaving)
                }
            }
        }
    }

    var isValidURL: Bool { URL(string: urlString)?.scheme?.hasPrefix("http") == true }

    func add() {
        if let url = URL(string: urlString) {
            isSaving = true; errorMessage = nil
            Task {
                let icon = await faviconService.resolveIcon(for: url)
                let feed = Feed(title: title.isEmpty ? (url.host ?? "Feed") : title, url: url, iconURL: icon)
                onAdd(feed)
                isSaving = false
                dismiss()
            }
        } else {
            isSaving = false
            errorMessage = "Invalid URL"
        }
    }
}

// MARK: - Add Folder UI
struct AddFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    var onAdd: (Folder) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Folder name", text: $name)
                }
            }
            .navigationTitle("Add Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onAdd(Folder(name: trimmed))
                        dismiss()
                    } label: {
                        Text("Add")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Safari wrapper


// MARK: - WebLink for sheet(item:)


// MARK: - Floating Day Indicator support


// MARK: - Concurrency control gate (semaphore-like)


// MARK: - App entry
struct ContentView: View {
    @StateObject private var store = FeedStore()
    @State private var selectedSource: Source?
    @State private var showingAdd = false
    @State private var showingAddFolder = false
    @State private var movingSource: Source?
    @State private var showingMoveDialog = false
    @State private var refreshID = UUID()
    @State private var isRefreshingAll = false
    @State private var refreshTotal: Int = 0
    @State private var refreshCompleted: Int = 0
    @State private var refreshArticlesCachedThisRun: Int = 0
    @State private var refreshArticlesSkippedThisRun: Int = 0
    @State private var currentRefreshRunID = UUID()
    @State private var cooldownUntil: Date? = nil
    @AppStorage("lastRefreshAllDate") private var lastRefreshAllDate: Double = 0 // seconds since 1970
    @State private var areSourcesCollapsed: Bool = false

    // Sidebar hero card data
    @State private var heroEntries: [SidebarHeroCardView.Entry] = []
    @State private var isLoadingHero: Bool = false
    private let heroCacheKey = "viberss.heroEntries"

    private let refreshService = FeedService()

    // Concurrency limits and gates for controlled caching
    private let maxConcurrentFeeds = 2
    private let maxPrefetchPerFeed = 6
    private let maxConcurrentArticlePrefetch = 1
    private let interBatchDelayNs: UInt64 = 150_000_000 // 150ms

    private let feedGate = ConcurrencyGate(limit: 2)
    private let articleGate = ConcurrencyGate(limit: 3)

    private func refreshAll() async {
        let runID = currentRefreshRunID
        let feeds = store.feeds
        let snapshotFeeds = feeds
        if Task.isCancelled { return }
        await MainActor.run {
            // Initialize counters for new run
            refreshTotal = feeds.count
            refreshCompleted = 0
            refreshArticlesCachedThisRun = 0
            refreshArticlesSkippedThisRun = 0
        }

        await withTaskGroup(of: Void.self) { group in
            for feed in snapshotFeeds {
                group.addTask {
                    if Task.isCancelled { return }
                    await feedGate.withPermit {
                        defer {
                            Task { @MainActor in
                                if isRefreshingAll && runID == currentRefreshRunID {
                                    refreshCompleted += 1
                                }
                            }
                        }
                        do {
                            let items = try await refreshService.loadItems(from: feed.url)
                            try Task.checkCancellation()
                            if Task.isCancelled { return }

                            // Limit how many we prefetch per feed
                            let limited = Array(items.prefix(maxPrefetchPerFeed))

                            // Process in small batches to avoid spikes
                            let batchSize = max(1, maxConcurrentArticlePrefetch)
                            var index = 0
                            while index < limited.count {
                                if Task.isCancelled { return }
                                let end = min(index + batchSize, limited.count)
                                let batch = limited[index..<end]

                                await withTaskGroup(of: Void.self) { inner in
                                    for item in batch {
                                        inner.addTask {
                                            if Task.isCancelled { return }
                                            if Task.isCancelled { return }
                                            await articleGate.withPermit {
                                                // Skip if already cached
                                                if await ArticleTextCache.shared.cachedText(for: item.link) != nil {
                                                    await MainActor.run { refreshArticlesSkippedThisRun += 1 }
                                                    return
                                                }
                                                if Task.isCancelled { return }
                                                do {
                                                    try Task.checkCancellation()
                                                    try await withTimeout(5.0) {
                                                        try Task.checkCancellation()
                                                        let html = try await ArticleSummarizer.shared.fetchHTML(url: item.link)
                                                        try Task.checkCancellation()
                                                        let limitedHTML = String(html.prefix(160_000))
                                                        let text = ArticleSummarizer.shared.extractReadableText(from: limitedHTML)
                                                        try Task.checkCancellation()
                                                        if !text.isEmpty {
                                                            await ArticleTextCache.shared.storeText(text, for: item.link)
                                                            await MainActor.run { refreshArticlesCachedThisRun += 1 }
                                                        }
                                                    }
                                                } catch {
                                                    // Ignore per-item errors (including timeouts)
                                                }
                                            }
                                        }
                                    }
                                    for await _ in inner { }
                                    if Task.isCancelled { return }
                                }

                                // Small pause between batches to keep UI responsive
                                try? await Task.sleep(nanoseconds: interBatchDelayNs)
                                try Task.checkCancellation()
                                if Task.isCancelled { return }
                                index = end
                            }
                        } catch {
                            // Ignore individual failures for the global refresh
                        }
                    }
                }
            }
            for await _ in group { }
        }
    }

    private func withTimeout<T>(_ seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            guard let result = try await group.next() else {
                group.cancelAll()
                throw URLError(.unknown)
            }
            group.cancelAll()
            return result
        }
    }

    private func relativeTimeString(since date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return "just now"
        }
        let minutes = (seconds + 59) / 60 // round up
        if minutes < 60 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }
        let hours = (minutes + 59) / 60 // round up
        if hours < 24 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        let days = (hours + 23) / 24 // round up
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    private func oneSentence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let dot = trimmed.firstIndex(of: ".") {
            let first = String(trimmed[..<trimmed.index(after: dot)])
            return String(first.prefix(140))
        }
        return String(trimmed.prefix(140))
    }

    private func saveHeroEntriesToCache() {
        do {
            let data = try JSONEncoder().encode(heroEntries)
            UserDefaults.standard.set(data, forKey: heroCacheKey)
        } catch {
            // Ignore cache write errors
        }
    }

    private func loadHeroEntriesFromCache() {
        if let data = UserDefaults.standard.data(forKey: heroCacheKey) {
            if let decoded = try? JSONDecoder().decode([SidebarHeroCardView.Entry].self, from: data) {
                heroEntries = decoded
            }
        }
    }
    
    @MainActor private func loadHeroEntries() async {
        guard !isLoadingHero else { return }
        isLoadingHero = true
        defer { isLoadingHero = false }
        let feeds = Array(store.feeds.prefix(5))
        var built: [SidebarHeroCardView.Entry] = []
        await withTaskGroup(of: SidebarHeroCardView.Entry?.self) { group in
            for feed in feeds {
                group.addTask {
                    do {
                        let items = try await self.refreshService.loadItems(from: feed.url)
                        guard let latest = items.sorted(by: { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }).first else {
                            return nil
                        }
                        let length: ArticleSummarizer.Length = .short
                        if let cached = await ArticleSummarizer.shared.cachedSummary(for: latest.link, length: length) {
                            let one = self.oneSentence(from: cached)
                            return SidebarHeroCardView.Entry(source: feed, title: latest.title, oneLine: one, link: latest.link)
                        } else {
                            var collected = ""
                            let stream = await ArticleSummarizer.shared.streamSummary(url: latest.link, length: .short, seedText: latest.summary)
                            var tokenCount = 0
                            for await partial in stream {
                                collected = partial
                                tokenCount += 1
                                if tokenCount >= 40 { break }
                            }
                            let one = self.oneSentence(from: collected)
                            return SidebarHeroCardView.Entry(source: feed, title: latest.title, oneLine: one, link: latest.link)
                        }
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                if let entry = result { built.append(entry) }
            }
        }
        built.sort { $0.source.title.localizedCaseInsensitiveCompare($1.source.title) == .orderedAscending }
        heroEntries = built
        saveHeroEntriesToCache()
    }

    @ViewBuilder private var sidebar: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                Section {
                    NavigationLink {
                        TodayView(refreshID: refreshID)
                            .environmentObject(store)
                    } label: {
                        Label("Today", systemImage: "sparkles.rectangle.stack")
                            .contentShape(Rectangle())
                    }

                    NavigationLink {
                        AllArticlesView(refreshID: refreshID)
                            .environmentObject(store)
                    } label: {
                        Label("All Articles", systemImage: "newspaper.fill")
                            .contentShape(Rectangle())
                    }
                    // Removed .simultaneousGesture to fix tap target and refresh bug

                    ForEach(store.folders) { folder in
                        NavigationLink {
                            FolderDetailView(folder: folder, refreshID: refreshID)
                                .environmentObject(store)
                        } label: {
                            HStack {
                                Label(folder.name, systemImage: "folder")
                                Spacer()
                                Text("\(store.feeds.filter { $0.folderID == folder.id }.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        // Removed .simultaneousGesture to fix tap target and refresh bug
                        .swipeActions {
                            Button(role: .destructive) {
                                store.removeFolder(folder)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                header: {
                    HStack(spacing: 8) {
                        Text("Folders")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .imageScale(.medium)
                            .rotationEffect(.degrees(0))
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { }
                }

                Section {
                    Group {
                        if !areSourcesCollapsed {
                            ForEach(store.feeds) { source in
                                NavigationLink {
                                    FeedDetailView(source: source, refreshID: refreshID)
                                } label: {
                                    HStack(spacing: 12) {
                                        FeedIconView(iconURL: source.iconURL)
                                        Text(source.title)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .contextMenu {
                                    Button("Refresh Icon") {
                                        Task { await store.refreshIcon(for: source) }
                                    }
                                    Menu("Move to Folder") {
                                        ForEach(store.folders) { folder in
                                            Button(folder.name) {
                                                store.assign(source, to: folder)
                                            }
                                        }
                                        if source.folderID != nil {
                                            Button("Remove from Folder") {
                                                store.assign(source, to: nil)
                                            }
                                        }
                                    }
                                }
                                .swipeActions {
                                    if source.folderID != nil {
                                        Button("Remove", role: .destructive) {
                                            store.assign(source, to: nil)
                                        }
                                    }
                                    Button("Move") {
                                        movingSource = source
                                        showingMoveDialog = true
                                    }
                                    Button("Delete", role: .destructive) {
                                        if let idx = store.feeds.firstIndex(where: { $0.id == source.id }) {
                                            store.feeds.remove(at: idx)
                                            if selectedSource?.id == source.id {
                                                selectedSource = store.feeds.first
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                } header: {
                    HStack(spacing: 8) {
                        Text("Sources")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .imageScale(.medium)
                            .rotationEffect(.degrees(areSourcesCollapsed ? 0 : 90))
                            .animation(.snappy(duration: 0.2), value: areSourcesCollapsed)
                        Spacer()
                        Text("\(store.feeds.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.snappy(duration: 0.25)) { areSourcesCollapsed.toggle() } }
                }
                .animation(.snappy(duration: 0.25), value: areSourcesCollapsed)
            }
            .navigationTitle("TodayRSS")
            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        let label: String = {
                            if lastRefreshAllDate > 0 {
                                let last = Date(timeIntervalSince1970: lastRefreshAllDate)
                                return "Updated \(relativeTimeString(since: last))"
                            } else {
                                return "Never updated"
                            }
                        }()
                        Text(label)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 0)
                    .padding(.leading, 16)
                    .padding(.trailing, 16)
                    .padding(.bottom, 6)

                    if !heroEntries.isEmpty {
                        SidebarHeroCardView(entries: heroEntries)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingAddFolder = true } label: { Image(systemName: "folder.badge.plus") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddFeedView { newSource in
                    store.feeds.append(newSource)
                    selectedSource = newSource
                }
                .environmentObject(store)
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingAddFolder) {
                AddFolderView { newFolder in
                    store.folders.append(newFolder)
                }
                .presentationDetents([.medium])
            }
            .confirmationDialog("Move to Folder", isPresented: $showingMoveDialog, presenting: movingSource) { source in
                ForEach(store.folders) { folder in
                    Button(folder.name) {
                        store.assign(source, to: folder)
                    }
                }
                if source.folderID != nil {
                    Button("Remove from Folder", role: .destructive) {
                        store.assign(source, to: nil)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { source in
                Text("Choose a folder for \(source.title)")
            }

            FloatingRefreshButton(isLoading: isRefreshingAll) {
                // Cooldown: prevent immediate re-entry for 1.5s after a run
                if let until = cooldownUntil, until > Date() { return }
                guard !isRefreshingAll else { return }
                isRefreshingAll = true
                currentRefreshRunID = UUID()
                let localRunID = currentRefreshRunID
                Task {
                    await feedGate.reset()
                    await articleGate.reset()
                    await MainActor.run {
                        // Initialize counters for new run
                        refreshCompleted = 0
                        refreshTotal = store.feeds.count
                        refreshArticlesCachedThisRun = 0
                        refreshArticlesSkippedThisRun = 0
                    }
                    do {
                        try await withTimeout(30.0) { await refreshAll() }
                    } catch {
                        await feedGate.reset()
                        await articleGate.reset()
                        // Watchdog fired; continue to reset UI state
                    }
                    // Bump ID so destination views update
                    await MainActor.run {
                        // Bump ID so destination views update
                        refreshID = UUID()
                        Task { await loadHeroEntries() }
                        // Mark refresh finished and immediately reset counters
                        isRefreshingAll = false
                        refreshCompleted = 0
                        refreshTotal = 0
                        refreshArticlesCachedThisRun = 0
                        refreshArticlesSkippedThisRun = 0
                        // Set cooldown 1.5s to avoid overlapping runs
                        lastRefreshAllDate = Date().timeIntervalSince1970
                        cooldownUntil = Date().addingTimeInterval(1.5)
                    }
                    // Removed delayed reset and second MainActor.run block
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 24)

            // Bottom linear progress bar for global refresh
            VStack {
                Spacer()
                if isRefreshingAll {
                    HStack(spacing: 10) {
                        ProgressView(value: Double(refreshCompleted), total: Double(refreshTotal))
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Refreshing feeds: \(refreshCompleted)/\(refreshTotal)")
                            Text("Cached (new): \(refreshArticlesCachedThisRun)")
                            Text("Skipped (already cached): \(refreshArticlesSkippedThisRun)")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(Color.secondary.opacity(0.2))
                    )
                    .padding(.bottom, 8)
                }
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var detailView: some View {
        if let source = selectedSource ?? store.feeds.first {
            FeedDetailView(source: source, refreshID: refreshID)
        } else {
            ContentPlaceholder()
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationDestination(for: Source.self) { source in
            FeedDetailView(source: source, refreshID: refreshID)
        }
        .onAppear {
            selectedSource = store.feeds.first
            store.backfillIcons()
            // Load cached hero entries first so the card shows immediately on launch
            loadHeroEntriesFromCache()
            // If no cache exists (first launch), build once and cache
            if heroEntries.isEmpty {
                Task { await loadHeroEntries() }
            }
        }
    }
}

@main
struct VibeRSSApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

// Inserted actor ArticleTextCache immediately above MARK: - ArticleSummarizer


// MARK: - ArticleSummarizer
actor ArticleSummarizer {
    static let shared = ArticleSummarizer()

    enum Length {
        case short, long
    }

    private var cache: [String: String] = [:] // key: "<url>#<length>"
    private let cacheStoreKey = "viberss.summaryCache"
    private let expandedStoreKey = "viberss.summaryExpanded"
    private var expandedState: Set<String> = [] // keys: "<url>#<length>"

    private var saveCacheDebounceTask: Task<Void, Never>? = nil
    private var saveExpandedDebounceTask: Task<Void, Never>? = nil

    // Nonisolated hint to quickly know if a cached summary likely exists (read-only from UserDefaults)
    nonisolated static func hasCachedSummary(url: URL, length: Length) -> Bool {
        // Reconstruct the key format used for storage
        let len = (length == .long) ? "long" : "short"
        let key = url.absoluteString + "#" + len
        // Read the serialized cache dictionary directly (avoids awaiting the actor)
        if let data = UserDefaults.standard.data(forKey: "viberss.summaryCache"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            return dict[key] != nil
        }
        return false
    }

    init() {
        cache = Self.loadCacheFromDefaults()
        expandedState = Self.loadExpandedFromDefaults()
    }

    private static func loadCacheFromDefaults() -> [String: String] {
        if let data = UserDefaults.standard.data(forKey: "viberss.summaryCache"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            return dict
        }
        return [:]
    }

    private static func loadExpandedFromDefaults() -> Set<String> {
        if let data = UserDefaults.standard.data(forKey: "viberss.summaryExpanded"),
           let set = try? JSONDecoder().decode(Set<String>.self, from: data) {
            return set
        }
        return []
    }

    private func saveCache() {
        saveCacheDebounceTask?.cancel()
        guard let data = try? JSONEncoder().encode(cache) else { return }
        saveCacheDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            UserDefaults.standard.set(data, forKey: cacheStoreKey)
        }
    }

    private func saveExpanded() {
        saveExpandedDebounceTask?.cancel()
        guard let data = try? JSONEncoder().encode(expandedState) else { return }
        saveExpandedDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            UserDefaults.standard.set(data, forKey: expandedStoreKey)
        }
    }

    func clearCache() {
        cache.removeAll()
        expandedState.removeAll()
        UserDefaults.standard.removeObject(forKey: cacheStoreKey)
        UserDefaults.standard.removeObject(forKey: expandedStoreKey)
    }

    func cachedSummary(for url: URL, length: Length) -> String? {
        let key = makeCacheKey(url: url, length: length)
        return cache[key]
    }

    func isExpanded(url: URL, length: Length) async -> Bool {
        expandedState.contains(makeCacheKey(url: url, length: length))
    }

    func setExpanded(_ expanded: Bool, url: URL, length: Length) async {
        let key = makeCacheKey(url: url, length: length)
        if expanded {
            expandedState.insert(key)
        } else {
            expandedState.remove(key)
        }
        saveExpanded()
    }

    private func makeCacheKey(url: URL, length: Length) -> String {
        let len = (length == .long) ? "long" : "short"
        return url.absoluteString + "#" + len
    }

    // Inserted helper function as requested:
    private func selectStructureAwareSlice(from text: String, targetChars: Int) -> String {
        guard !text.isEmpty, targetChars > 0 else { return "" }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let normalizedBreaks = normalized.replacingOccurrences(of: "\\n{2,}", with: "\\n\\n", options: .regularExpression)

        let rawParas = normalizedBreaks.components(separatedBy: "\n\n")
        // Trim, then drop boilerplate-y, too-short, or too-long paragraphs to reduce noise
        let paragraphs: [String] = rawParas
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { p in
                let lower = p.lowercased()
                if lower.contains("related posts") || lower.contains("read more") || lower.contains("subscribe") || lower.contains("newsletter") || lower.contains("sponsored") || lower.contains("advertisement") {
                    return false
                }
                let count = p.count
                if count < 30 { return false }
                if count > 1200 { return false }
                return true
            }
        let paragraphsCapped = Array(paragraphs.prefix(60))

        if paragraphsCapped.isEmpty { return String(text.prefix(targetChars)) }

        func isHeading(_ s: String) -> Bool {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            if trimmed.count <= 80 && trimmed.last == ":" { return true }
            let words = trimmed.split(separator: " ")
            let capCount = words.filter { w in
                guard let f = w.first else { return false }
                return String(f).uppercased() == String(f) && w.count > 2
            }.count
            if words.count > 0 && capCount * 2 >= words.count { return true }
            let letters = trimmed.filter { $0.isLetter }
            if !letters.isEmpty {
                let upper = letters.filter { String($0) == String($0).uppercased() }
                if letters.count <= 80 && upper.count * 3 >= letters.count * 2 { return true }
            }
            return false
        }

        let n = paragraphsCapped.count
        var selected = Set<Int>()
        if n >= 1 { selected.insert(0) }
        if n >= 2 { selected.insert(1) }
        if n >= 3 { selected.insert(n - 1) }
        for i in 0..<n where isHeading(paragraphsCapped[i]) {
            if i > 0 { selected.insert(i - 1) }
            selected.insert(i)
            if i + 1 < n { selected.insert(i + 1) }
        }
        func currentLength(_ indices: Set<Int>) -> Int {
            indices.sorted().map { paragraphsCapped[$0] }.reduce(0) { $0 + $1.count + 2 }
        }
        var lengthNow = currentLength(selected)
        if lengthNow >= targetChars {
            let ordered = selected.sorted().map { paragraphsCapped[$0] }
            let joined = ordered.joined(separator: "\n\n")
            return joined.count <= targetChars ? joined : String(joined.prefix(targetChars))
        }
        var candidates: [Int] = []
        if n > 4 {
            let start = 2, end = n - 2
            if start < end {
                let span = end - start
                let step = max(1, span / 8)
                var i = start
                while i < end {
                    if !selected.contains(i) { candidates.append(i) }
                    i += step
                }
            }
        }
        if candidates.isEmpty {
            for i in 0..<n where !selected.contains(i) { candidates.append(i) }
        }
        for idx in candidates {
            if lengthNow >= targetChars { break }
            selected.insert(idx)
            lengthNow = currentLength(selected)
        }
        let ordered = selected.sorted().map { paragraphsCapped[$0] }
        let joined = ordered.joined(separator: "\n\n")
        return joined.count <= targetChars ? joined : String(joined.prefix(targetChars))
    }

    // Insert the new helper method selectPrimerSlice as requested:
    private func selectPrimerSlice(from text: String, maxChars: Int) -> String {
        guard !text.isEmpty, maxChars > 0 else { return "" }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let normalizedBreaks = normalized.replacingOccurrences(of: "\\n{2,}", with: "\\n\\n", options: .regularExpression)
        let rawParas = normalizedBreaks.components(separatedBy: "\n\n")
        // Very lightweight filtering: trim and drop empty; keep modest length ranges only
        let paragraphs: [String] = rawParas
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { p in
                let c = p.count
                return c >= 30 && c <= 1200
            }
        if paragraphs.isEmpty { return String(text.prefix(maxChars)) }
        // Take the first 2–3 paragraphs that fit within maxChars
        var picked: [String] = []
        var total = 0
        for p in paragraphs.prefix(3) {
            if total + p.count + (picked.isEmpty ? 0 : 2) > maxChars { break }
            picked.append(p)
            total += p.count + (picked.count > 1 ? 2 : 0)
        }
        if picked.isEmpty { return String(paragraphs.first!.prefix(maxChars)) }
        let joined = picked.joined(separator: "\n\n")
        return joined.count <= maxChars ? joined : String(joined.prefix(maxChars))
    }

    func streamSummary(url: URL, length: Length, seedText: String?) async -> AsyncStream<String> {
        AsyncStream { continuation in
            let worker = Task {
                let key = makeCacheKey(url: url, length: length)
                if let cached = cache[key] {
                    continuation.yield(cached)
                    continuation.finish()
                    return
                }
                if Task.isCancelled { continuation.finish(); return }

#if canImport(FoundationModels)
                let model = SystemLanguageModel.default
                guard case .available = model.availability else {
                    continuation.finish()
                    return
                }

                // Try preloaded readable text first; otherwise fetch and extract
                let cachedText = await ArticleTextCache.shared.cachedText(for: url)
                let baseText: String
                if let cachedText, !cachedText.isEmpty {
                    baseText = String(cachedText.prefix(250_000))
                } else {
                    guard let html = try? await fetchHTML(url: url) else {
                        continuation.finish()
                        return
                    }
                    let limitedHTML = String(html.prefix(250_000))
                    let extracted = extractReadableText(from: limitedHTML)
                    if extracted.isEmpty {
                        continuation.finish()
                        return
                    }
                    baseText = extracted
                    await ArticleTextCache.shared.storeText(extracted, for: url)
                }

                let instructions: String = {
                    switch length {
                    case .short:
                        return "Summarize in 1 sentence (≤60 words). Focus only on key facts, outcomes, numbers, and decisions. Omit background, adjectives, and repetition. No bullet points."
                    case .long:
                        return "Summarize for busy readers in 3–6 sentences (<200 words). Focus on key facts, context, implications. No fluff. Avoid repetition."
                    }
                }()

                // Build a prompt using extracted text, optionally including a small portion of the feed's seed text for context.
                var prompt = "Summarize this article:\n\n"
                if let seed = seedText?.trimmingCharacters(in: .whitespacesAndNewlines), !seed.isEmpty {
                    let s = String(seed.prefix(900))
                    prompt += "Preview/context from feed:\n\(s)\n\n"
                }

                // Replace the switch on length with the new code for .short:
                switch length {
                case .short:
                    // Stage 1: quick primer slice to reduce time-to-first-token
                    let primer = self.selectPrimerSlice(from: baseText, maxChars: 1000)
                    let promptPrimer = prompt + primer
                    do {
                        let sessionPrimer = LanguageModelSession(instructions: instructions)
                        let streamPrimer = sessionPrimer.streamResponse(to: promptPrimer, generating: InlineSummary.self)
                        var finalTextPrimer: String = ""
                        var revealedCountPrimer: Int = 0
                        let step = 2
                        let stepDelay: UInt64 = 30_000_000 // 30 ms
                        for try await partial in streamPrimer {
                            if Task.isCancelled { continuation.finish(); return }
                            guard let t = partial.content.text, !t.isEmpty else { continue }
                            finalTextPrimer = t
                            if t.count <= revealedCountPrimer { continue }
                            var target = min(revealedCountPrimer + step, t.count)
                            while target < t.count {
                                let idx = t.index(t.startIndex, offsetBy: target)
                                let prefix = String(t[..<idx])
                                continuation.yield(prefix)
                                revealedCountPrimer = target
                                try? await Task.sleep(nanoseconds: stepDelay)
                                if Task.isCancelled { continuation.finish(); return }
                                target = min(revealedCountPrimer + step, t.count)
                            }
                            continuation.yield(t)
                            revealedCountPrimer = t.count
                        }
                        if !finalTextPrimer.isEmpty {
                            self.cache[key] = finalTextPrimer
                            self.saveCache()
                            // If the primer result is reasonably sized, finish here for speed
                            if finalTextPrimer.count >= 120 { // heuristic threshold
                                continuation.finish()
                                return
                            }
                        }
                    } catch {
                        // Ignore primer stage errors and fall back to full body
                    }
                    // Stage 2: full short body (structure-aware ~6000 chars) if primer was too weak
                    let selected = self.selectStructureAwareSlice(from: baseText, targetChars: 6000)
                    let fullBody = String(selected.prefix(6000))
                    let sessionFull = LanguageModelSession(instructions: instructions)
                    let streamFull = sessionFull.streamResponse(to: prompt + fullBody, generating: InlineSummary.self)
                    var finalTextFull: String = ""
                    var revealedCountFull: Int = 0
                    let step = 2
                    let stepDelay: UInt64 = 30_000_000 // 30 ms
                    for try await partial in streamFull {
                        if Task.isCancelled { continuation.finish(); return }
                        guard let t = partial.content.text, !t.isEmpty else { continue }
                        finalTextFull = t
                        if t.count <= revealedCountFull { continue }
                        var target = min(revealedCountFull + step, t.count)
                        while target < t.count {
                            let idx = t.index(t.startIndex, offsetBy: target)
                            let prefix = String(t[..<idx])
                            continuation.yield(prefix)
                            revealedCountFull = target
                            try? await Task.sleep(nanoseconds: stepDelay)
                            if Task.isCancelled { continuation.finish(); return }
                            target = min(revealedCountFull + step, t.count)
                        }
                        continuation.yield(t)
                        revealedCountFull = t.count
                    }
                    if !finalTextFull.isEmpty {
                        self.cache[key] = finalTextFull
                        self.saveCache()
                    }
                    continuation.finish()
                    return
                case .long:
                    // Two-stage strategy for faster TTFB while preserving accuracy
                    let instructions = """
Summarize for busy readers in 3–6 sentences (<200 words).
Focus on key facts, context, implications, and preserve numerical details.
Preserve qualifiers (e.g., “may”, “could”, “report suggests”) and avoid overstating certainty.
Do not introduce any information that isn’t present in the text.
Avoid repetition and adjectives.
"""

                    // Build a prompt using extracted text, optionally including a small portion of the feed's seed text for context.
                    var promptBase = "Summarize this article:\n\n"
                    if let seed = seedText?.trimmingCharacters(in: .whitespacesAndNewlines), !seed.isEmpty {
                        let s = String(seed.prefix(900))
                        promptBase += "Preview/context from feed:\n\(s)\n\n"
                    }

                    // Stage 1: quick primer slice for immediate streaming
                    let primer = self.selectPrimerSlice(from: baseText, maxChars: 1400)
                    let promptPrimer = promptBase + primer
                    do {
                        let sessionPrimer = LanguageModelSession(instructions: instructions)
                        let streamPrimer = sessionPrimer.streamResponse(to: promptPrimer, generating: InlineSummary.self)
                        var finalTextPrimer: String = ""
                        var revealedCountPrimer: Int = 0
                        let step = 2
                        let stepDelay: UInt64 = 30_000_000 // 30 ms
                        for try await partial in streamPrimer {
                            if Task.isCancelled { continuation.finish(); return }
                            guard let t = partial.content.text, !t.isEmpty else { continue }
                            finalTextPrimer = t
                            if t.count <= revealedCountPrimer { continue }
                            var target = min(revealedCountPrimer + step, t.count)
                            while target < t.count {
                                let idx = t.index(t.startIndex, offsetBy: target)
                                let prefix = String(t[..<idx])
                                continuation.yield(prefix)
                                revealedCountPrimer = target
                                try? await Task.sleep(nanoseconds: stepDelay)
                                if Task.isCancelled { continuation.finish(); return }
                                target = min(revealedCountPrimer + step, t.count)
                            }
                            continuation.yield(t)
                            revealedCountPrimer = t.count
                        }
                        if !finalTextPrimer.isEmpty {
                            self.cache[key] = finalTextPrimer
                            self.saveCache()
                            // If the primer result is sufficiently informative, finish early
                            if finalTextPrimer.count >= 160 { // heuristic threshold
                                continuation.finish()
                                return
                            }
                        }
                    } catch {
                        // Ignore primer errors and proceed to full pass
                    }

                    // Stage 2: full structure-aware body for completeness
                    let selected = self.selectStructureAwareSlice(from: baseText, targetChars: 12_000)
                    let body = String(selected.prefix(12_000))
                    let promptFull = promptBase + body

                    do {
                        let sessionFull = LanguageModelSession(instructions: instructions)
                        let streamFull = sessionFull.streamResponse(to: promptFull, generating: InlineSummary.self)
                        var finalTextFull: String = ""
                        var revealedCountFull: Int = 0
                        let step = 2
                        let stepDelay: UInt64 = 30_000_000 // 30 ms

                        for try await partial in streamFull {
                            if Task.isCancelled { continuation.finish(); return }
                            guard let t = partial.content.text, !t.isEmpty else { continue }
                            finalTextFull = t

                            if t.count <= revealedCountFull { continue }
                            var target = min(revealedCountFull + step, t.count)
                            while target < t.count {
                                let idx = t.index(t.startIndex, offsetBy: target)
                                let prefix = String(t[..<idx])
                                continuation.yield(prefix)
                                revealedCountFull = target
                                try? await Task.sleep(nanoseconds: stepDelay)
                                if Task.isCancelled { continuation.finish(); return }
                                target = min(revealedCountFull + step, t.count)
                            }

                            continuation.yield(t)
                            revealedCountFull = t.count
                        }

                        if !finalTextFull.isEmpty {
                            self.cache[key] = finalTextFull
                            self.saveCache()
                        }
                        continuation.finish()
                        return
                    } catch {
                        continuation.finish()
                        return
                    }
                }
#else
                continuation.finish()
#endif
            }
            continuation.onTermination = { _ in
                worker.cancel()
            }
        }
    }

    func fetchHTML(url: URL) async throws -> String {
        try Task.checkCancellation()
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 3)
        let (data, _) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated func extractReadableText(from html: String) -> String {
        if html.isEmpty { return "" }
        if Task.isCancelled { return "" }
        // Work on a limited slice to speed up regex processing
        var s = String(html.prefix(200_000))
        if Task.isCancelled { return "" }
        // Remove comments
        s = s.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)

        // Prefer <article> content if present
        if let range = s.range(of: "<article[\\n\\r\\s\\S]*?</article>", options: .regularExpression) {
            s = String(s[range])
        }
        if Task.isCancelled { return "" }

        // Remove common boilerplate blocks
        let blocks = ["nav", "header", "footer", "aside"]
        for tag in blocks {
            if let regex = try? NSRegularExpression(pattern: "<" + tag + "[\\n\\r\\s\\S]*?</" + tag + ">", options: [.caseInsensitive]) {
                s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
            }
        }

        // Remove scripts and styles
        if let regex = try? NSRegularExpression(pattern: "<script[\\n\\r\\s\\S]*?</script>", options: [.caseInsensitive]) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
        }
        if Task.isCancelled { return "" }
        if let regex = try? NSRegularExpression(pattern: "<style[\\n\\r\\s\\S]*?</style>", options: [.caseInsensitive]) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
        }

        // Strip all tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
        }
        if Task.isCancelled { return "" }

        // Decode HTML entities roughly by letting AttributedString handle some
        let attr = try? AttributedString(markdown: s)
        let plain = attr?.description ?? s

        // Collapse whitespace
        let collapsed = plain.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression, range: nil)
        if Task.isCancelled { return "" }
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func chunk(text: String, size: Int, overlap: Int = 0) -> [String] {
        guard !text.isEmpty, size > 0 else { return [] }
        var result: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            let slice = String(text[start..<end])
            result.append(slice)
            if end == text.endIndex { break }
            let nextStart = overlap > 0 ? text.index(end, offsetBy: -min(overlap, size), limitedBy: text.startIndex) ?? end : end
            start = nextStart
        }
        return result
    }
}

