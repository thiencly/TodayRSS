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


// MARK: - Shared Siri-like Gradient & Glow








// MARK: - Models





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
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(2)
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
                            .padding(.top, 4)

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
            ReaderSafariView(url: w.url).ignoresSafeArea()
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
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(2)
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
                            .padding(.top, 4)

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
            ReaderSafariView(url: w.url).ignoresSafeArea()
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
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(2)
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
                            .padding(.top, 4)

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
            ReaderSafariView(url: w.url).ignoresSafeArea()
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
struct CurrentView: View {
    @EnvironmentObject private var store: FeedStore
    var refreshID: UUID = UUID()

    @State private var items: [Article] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    @State private var webLink: WebLink?
    @State private var summarizingID: UUID?
    @State private var inlineSummaries: [UUID: String] = [:]
    @State private var expandedSummaries: Set<UUID> = []
    @State private var summaryErrors: Set<UUID> = []
    @State private var hasCachedText: Set<UUID> = []

    @AppStorage("summaryLength") private var summaryLengthRaw: String = "short"
    @State private var aiSummarized: Set<UUID> = []
    @State private var currentDay: Date? = nil
    @State private var suppressNextRowTap = false

    private let service = FeedService()

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView().controlSize(.large)
            } else if let errorMessage, items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(errorMessage).multilineTextAlignment(.center)
                    Button("Retry") { Task { await loadLatestPerSource() } }
                }.padding()
            } else {
                List(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline)
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(2)
                                .contentShape(Rectangle())
                                .onTapGesture { webLink = WebLink(url: item.link) }

                            Group {
                                let isError = summaryErrors.contains(item.id)
                                let aiSummary = inlineSummaries[item.id]

                                HStack(spacing: 6) {
                                    SummarizeButton(
                                        state: { () -> SummarizeButton.ButtonState in
                                            if summarizingID == item.id { return .generating }
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
                                            let hasCached = (aiSummary != nil) || ArticleSummarizer.hasCachedSummary(url: item.link, length: length)
                                            if hasCached { return .hasSummary(isExpanded: expandedSummaries.contains(item.id)) }
                                            return .none
                                        }()
                                    ) {
                                        suppressNextRowTap = true
                                        let hasSummary = (aiSummary != nil)
                                        if hasSummary {
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
                                            if expandedSummaries.contains(item.id) {
                                                withAnimation(.easeInOut(duration: 0.2)) { expandedSummaries.remove(item.id) }
                                                Task { await ArticleSummarizer.shared.setExpanded(false, url: item.link, length: length) }
                                            } else {
                                                withAnimation(.easeInOut(duration: 0.2)) { expandedSummaries.insert(item.id) }
                                                Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
                                            }
                                        } else if summarizingID != item.id {
                                            Task { await summarize(item) }
                                        }
                                    }
                                    .disabled(isError)

                                    if hasCachedText.contains(item.id) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                            .accessibilityLabel("Cached text available")
                                    }
                                }

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
                            }
                            .padding(.top, 4)

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
                                .onTapGesture { webLink = WebLink(url: item.link) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DayAnchorReporter(date: item.pubDate, coordinateSpaceName: "CurrentListScroll"))
                    .id(item.id)
                    .transaction { $0.disablesAnimations = false }
                }
                .listStyle(.plain)
                .transaction { $0.animation = nil }
                .refreshable { await loadLatestPerSource() }
                .coordinateSpace(name: "CurrentListScroll")
                .task(id: items.map { $0.id }) { preloadSummaries(for: items) }
                .onChange(of: summaryLengthRaw) { _, _ in }
                .onPreferenceChange(DayAnchorsKey.self) { anchors in
                    guard !anchors.isEmpty else { currentDay = nil; return }
                    let sorted = anchors.sorted { a, b in
                        let aScore = (a.minY >= 0) ? a.minY : (100000 + abs(a.minY))
                        let bScore = (b.minY >= 0) ? b.minY : (100000 + abs(b.minY))
                        return aScore < bScore
                    }
                    let topDay = sorted.first?.dayStart
                    if currentDay != topDay {
                        withAnimation(.easeInOut(duration: 0.15)) { currentDay = topDay }
                    }
                }
                // Removed safeAreaInset(edge: .top) from CurrentView as requested
            }
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingRefreshButton(isLoading: isLoading) {
                Task { await loadLatestPerSource() }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 24)
        }
        .task(id: refreshID) { await loadLatestPerSource() }
        .navigationTitle("Current")
        .sheet(item: $webLink) { w in
            ReaderSafariView(url: w.url).ignoresSafeArea()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("Summary Length") {
                        Button {
                            summaryLengthRaw = "short"
                        } label: {
                            HStack { Text("Short"); if summaryLengthRaw == "short" { Image(systemName: "checkmark") } }
                        }
                        Button {
                            summaryLengthRaw = "long"
                        } label: {
                            HStack { Text("Long"); if summaryLengthRaw == "long" { Image(systemName: "checkmark") } }
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
                } label: { Image(systemName: "sparkles") }
            }
        }
    }

    private func loadLatestPerSource() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        let feeds = store.feeds
        var collected: [Article] = []
        let service = self.service
        await withTaskGroup(of: Article?.self) { group in
            for src in feeds {
                group.addTask {
                    do {
                        var items = try await service.loadItems(from: src.url)
                        for i in items.indices {
                            items[i].sourceID = src.id
                            items[i].sourceTitle = src.title
                            items[i].sourceIconURL = src.iconURL
                        }
                        guard let latest = items.sorted(by: { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }).first else {
                            return nil
                        }
                        return latest
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                if let a = result { collected.append(a) }
            }
        }
        collected.sort { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        await MainActor.run {
            self.items = collected
            self.isLoading = false
        }
    }

    private func preloadSummaries(for items: [Article]) {
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
        Task { @MainActor in
            var updated = inlineSummaries
            var expanded = expandedSummaries
            var cachedFlags = hasCachedText
            for item in items {
                if updated[item.id] == nil, let cached = await ArticleSummarizer.shared.cachedSummary(for: item.link, length: length) {
                    updated[item.id] = cached
                }
                if await ArticleSummarizer.shared.isExpanded(url: item.link, length: length) {
                    expanded.insert(item.id)
                } else {
                    expanded.remove(item.id)
                }
                if await ArticleTextCache.shared.cachedText(for: item.link) != nil {
                    cachedFlags.insert(item.id)
                } else {
                    cachedFlags.remove(item.id)
                }
            }
            inlineSummaries = updated
            expandedSummaries = expanded
            hasCachedText = cachedFlags
        }
    }

    @MainActor private func summarize(_ item: Article) async {
        summaryErrors.remove(item.id)
        summarizingID = item.id
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "long") ? .long : .short
        if !expandedSummaries.contains(item.id) {
            withAnimation(.easeInOut(duration: 0.2)) { expandedSummaries.insert(item.id) }
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
        if !sawAny { summaryErrors.insert(item.id) }
        summarizingID = nil
    }
}

// MARK: - Simple shimmer modifier for loading placeholders
private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        // Mask-based shimmer: the moving highlight is drawn and then
        // masked by the content so it only shows over the redacted shapes.
        content
            .overlay(
                GeometryReader { proxy in
                    let width = max(1, proxy.size.width)
                    let height = max(1, proxy.size.height)

                    // Primary multi-stop gradient with soft edges and a subtle tint
                    let primary = LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.0), location: 0.00),
                            .init(color: Color.white.opacity(0.08), location: 0.18),
                            .init(color: Color.white.opacity(0.35), location: 0.50),
                            .init(color: Color.white.opacity(0.08), location: 0.82),
                            .init(color: Color.white.opacity(0.0), location: 1.00)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Subtle colored sheen layered under the primary for a more gradient look
                    let tint = LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.blue.opacity(0.00), location: 0.00),
                            .init(color: Color.blue.opacity(0.10), location: 0.45),
                            .init(color: Color.purple.opacity(0.10), location: 0.55),
                            .init(color: Color.purple.opacity(0.00), location: 1.00)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    ZStack {
                        // Secondary wider band for depth
                        Rectangle()
                            .fill(tint)
                            .rotationEffect(.degrees(18))
                            .frame(width: width * 0.78, height: height * 1.8)
                            .offset(x: width * (phase - 0.12))
                            .blur(radius: 8)
                            .blendMode(.screen)

                        // Primary crisp band
                        Rectangle()
                            .fill(primary)
                            .rotationEffect(.degrees(20))
                            .frame(width: width * 0.64, height: height * 1.7)
                            .offset(x: width * phase)
                            .blur(radius: 2)
                            .blendMode(.screen)
                    }
                }
                .clipped()
                .allowsHitTesting(false)
            )
            // Ensure the shimmer only appears where the content is non-transparent
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
    }
}

private extension View {
    @ViewBuilder
    func shimmer(if condition: Bool) -> some View {
        if condition {
            self.modifier(Shimmer())
        } else {
            self
        }
    }
}

// Identity modifier helper
// REMOVED IdentityModifier struct as no longer needed

private struct SidebarHeroCardView: View {
    struct Entry: Identifiable, Hashable, Codable {
        let id = UUID()
        let source: Source
        let title: String
        let oneLine: String
        let link: URL
        let isNew: Bool
    }

    let entries: [Entry]
    var isUpdating: Bool = false
    var onTapLink: ((URL) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Inner content that should blur while loading
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    RainbowGlowSymbol(systemName: "sparkles", font: .caption, subtle: true)
                    Text("Today Highlights")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                }

                // Show real entries if present; otherwise show 3 placeholders
                Group {
                    if entries.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            placeholderRow
                        }
                    } else {
                        ForEach(entries.prefix(3)) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
            // Removed .blur(radius: isUpdating ? 8 : 0)
        }
        .padding(16)
        .background(
            ZStack {
                // Subtle Siri-like animated glow behind the card
                SiriGlow(cornerRadius: 22, opacity: 0.32)
                // Card material on top of glow
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
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
        .animation(.snappy(duration: 0.2), value: isUpdating)
    }

    @ViewBuilder
    private func entryRow(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                FeedIconView(iconURL: entry.source.iconURL)
                    .frame(width: 20, height: 20)
                Text(entry.source.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                if entry.isNew {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("New article")
                }
                Spacer()
            }
            Text(entry.oneLine.isEmpty ? entry.title : entry.oneLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTapLink?(entry.link) }
        .redacted(reason: isUpdating ? .placeholder : [])
        .shimmer(if: isUpdating)
    }

    private var placeholderRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2))
                    .frame(width: 20, height: 20)
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2))
                    .frame(width: 120, height: 12)
                Spacer()
            }
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2))
                .frame(height: 10)
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2))
                .frame(width: 180, height: 10)
        }
        .redacted(reason: .placeholder)
        .shimmer(if: true)
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

struct ReaderSafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.dismissButtonStyle = .close
        return vc
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}


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
    @State private var heroWebLink: WebLink? = nil
    @AppStorage("lastRefreshAllDate") private var lastRefreshAllDate: Double = 0 // seconds since 1970
    @State private var areSourcesCollapsed: Bool = false

    @Environment(\.scenePhase) private var scenePhase

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
        // Look for ., !, or ? as sentence terminators
        if let idx = trimmed.firstIndex(where: { [".", "!", "?"].contains($0) }) {
            return String(trimmed[..<trimmed.index(after: idx)])
        }
        // If no terminator, softly cap at a reasonable length but break at whitespace
        let softCap = 280
        if trimmed.count > softCap {
            let capIndex = trimmed.index(trimmed.startIndex, offsetBy: softCap, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            if let spaceIdx = trimmed[..<capIndex].lastIndex(of: " ") {
                return String(trimmed[..<spaceIdx])
            }
        }
        return trimmed
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
        let start = Date()
        defer {
            let elapsed = Date().timeIntervalSince(start)
            let minDuration = 0.25
            if elapsed < minDuration {
                Task { try? await Task.sleep(nanoseconds: UInt64((minDuration - elapsed) * 1_000_000_000)); isLoadingHero = false }
            } else {
                isLoadingHero = false
            }
        }
        let feeds = Array(store.feeds.prefix(3))
        // Capture previously seen links from cached hero entries to determine "new" status
        let previouslySeenLinks: Set<URL> = Set(heroEntries.map { $0.link })
        var built: [SidebarHeroCardView.Entry] = []
        await withTaskGroup(of: SidebarHeroCardView.Entry?.self) { group in
            for feed in feeds {
                group.addTask {
                    do {
                        let items = try await self.refreshService.loadItems(from: feed.url)
                        guard let latest = items.sorted(by: { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }).first else {
                            return nil
                        }
                        let length: ArticleSummarizer.Length = .quick
                        if let cached = await ArticleSummarizer.shared.cachedSummary(for: latest.link, length: length) {
                            let one = cached
                            let isNew = !previouslySeenLinks.contains(latest.link)
                            return SidebarHeroCardView.Entry(source: feed, title: latest.title, oneLine: one, link: latest.link, isNew: isNew)
                        } else {
                            var collected = ""
                            let stream = await ArticleSummarizer.shared.streamSummary(url: latest.link, length: .quick, seedText: latest.summary)
                            // Removed tokenCount and break to allow full streaming
                            for await partial in stream {
                                collected = partial
                            }
                            let one = collected
                            let isNew = !previouslySeenLinks.contains(latest.link)
                            return SidebarHeroCardView.Entry(source: feed, title: latest.title, oneLine: one, link: latest.link, isNew: isNew)
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
                        CurrentView(refreshID: refreshID)
                            .environmentObject(store)
                    } label: {
                        Label("Current", systemImage: "sparkles.rectangle.stack")
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
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        if let idx = store.feeds.firstIndex(where: { $0.id == source.id }) {
                                            store.feeds.remove(at: idx)
                                            if selectedSource?.id == source.id {
                                                selectedSource = store.feeds.first
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
                        SidebarHeroCardView(entries: heroEntries, isUpdating: isLoadingHero, onTapLink: { url in
                            heroWebLink = WebLink(url: url)
                        })
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Clear Hero Cache") {
                            // Clear cached hero entries and persisted storage; then reload
                            heroEntries.removeAll()
                            UserDefaults.standard.removeObject(forKey: heroCacheKey)
                            Task { await loadHeroEntries() }
                        }
                        Button("Clear All Summaries", role: .destructive) {
                            Task { await ArticleSummarizer.shared.clearCache() }
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .help("Cache Tools")
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
            .sheet(item: $heroWebLink) { w in
                ReaderSafariView(url: w.url).ignoresSafeArea()
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
            // Always show cached hero entries immediately (if any)
            loadHeroEntriesFromCache()
            // Always refresh hero entries on app open to fetch latest
            Task { await loadHeroEntries() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await loadHeroEntries() }
            }
        }
        .onChange(of: store.feeds) { _, _ in
            Task { await loadHeroEntries() }
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










