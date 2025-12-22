import SwiftUI

struct AddFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FeedStore

    var onAdd: (Source) -> Void

    @State private var searchQuery: String = ""
    @State private var searchResults: [FeedSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    @State private var manualURL: String = ""
    @State private var manualTitle: String = ""
    @State private var isAddingManual: Bool = false
    @State private var manualError: String?

    @State private var addingFeedID: String?
    @State private var showPaywall = false

    private let searchService = FeedSearchService()
    private let faviconService = FaviconService()

    var body: some View {
        NavigationStack {
            List {
                // Search Section
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search for RSS feeds...", text: $searchQuery)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit {
                                performSearch()
                            }
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                                searchResults = []
                                searchError = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Search")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Search by publication name, topic, or website")
                        Text("Tip: The Feedly database may contain outdated URLs that cause errors. If a source doesn't work, try selecting a different result with the same name or add the feed URL manually.")
                            .foregroundStyle(.orange)
                    }
                }

                // Search Results
                if isSearching {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 20)
                            Spacer()
                        }
                    }
                } else if let error = searchError {
                    Section {
                        Text(error)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                } else if !searchResults.isEmpty {
                    Section {
                        ForEach(searchResults) { result in
                            searchResultRow(result)
                        }
                    } header: {
                        Text("Results")
                    }
                } else if !searchQuery.isEmpty {
                    Section {
                        Text("No results found. Try a different search or add manually below.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }

                // Manual URL Section
                Section {
                    TextField("Feed URL (https://...)", text: $manualURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    TextField("Title (optional)", text: $manualTitle)

                    Button {
                        addManualFeed()
                    } label: {
                        HStack {
                            if isAddingManual {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Adding...")
                            } else {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Feed")
                            }
                        }
                    }
                    .disabled(!isValidManualURL || isAddingManual)

                    if let error = manualError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                } header: {
                    Text("Add Manually")
                } footer: {
                    Text("Paste a direct RSS/Atom feed URL if you can't find it via search")
                }
            }
            .navigationTitle("Add Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: searchQuery) { _, newValue in
                debounceSearch(query: newValue)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(trigger: .feeds)
            }
        }
    }

    // MARK: - Search Result Row

    @ViewBuilder
    private func searchResultRow(_ result: FeedSearchResult) -> some View {
        HStack(spacing: 12) {
            // Icon
            if let iconURL = result.iconURL {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        Image(systemName: "dot.radiowaves.up.forward")
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                            .scaleEffect(0.5)
                    @unknown default:
                        Image(systemName: "dot.radiowaves.up.forward")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.roundedHeadline)
                    .lineLimit(1)

                if let description = result.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let subscribers = result.subscribers, subscribers > 0 {
                    Text("\(formatSubscribers(subscribers)) subscribers")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Add Button
            if addingFeedID == result.id {
                ProgressView()
                    .scaleEffect(0.8)
            } else if isAlreadySubscribed(result) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    addSearchResult(result)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Search Logic

    private func debounceSearch(query: String) {
        searchTask?.cancel()

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            searchError = nil
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms debounce

            if Task.isCancelled { return }

            await performSearchAsync(query: query)
        }
    }

    private func performSearch() {
        searchTask?.cancel()
        Task {
            await performSearchAsync(query: searchQuery)
        }
    }

    @MainActor
    private func performSearchAsync(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isSearching = true
        searchError = nil

        do {
            let results = try await searchService.search(query: query)
            if !Task.isCancelled {
                searchResults = results
                if results.isEmpty {
                    searchError = nil
                }
            }
        } catch {
            if !Task.isCancelled {
                // Show more descriptive error message
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .notConnectedToInternet:
                        searchError = "No internet connection. Please check your network."
                    case .timedOut:
                        searchError = "Request timed out. Please try again."
                    case .cannotFindHost, .cannotConnectToHost:
                        searchError = "Cannot connect to search service. Please try again later."
                    default:
                        searchError = "Network error: \(urlError.localizedDescription)"
                    }
                } else {
                    searchError = "Search failed. Please try again."
                }
                searchResults = []
            }
        }

        isSearching = false
    }

    // MARK: - Add Feed Logic

    private func addSearchResult(_ result: FeedSearchResult) {
        // Check feed limit
        guard EntitlementManager.shared.canAddFeed(currentCount: store.feeds.count) else {
            showPaywall = true
            return
        }

        HapticManager.shared.click()
        addingFeedID = result.id

        Task {
            var icon = result.iconURL
            if icon == nil {
                icon = await faviconService.resolveIcon(for: result.feedURL)
            }
            let feed = Feed(
                title: result.title,
                url: result.feedURL,
                iconURL: icon
            )

            await MainActor.run {
                onAdd(feed)
                addingFeedID = nil
            }
        }
    }

    private var isValidManualURL: Bool {
        guard let url = URL(string: manualURL) else { return false }
        return url.scheme?.hasPrefix("http") == true
    }

    private func addManualFeed() {
        // Check feed limit
        guard EntitlementManager.shared.canAddFeed(currentCount: store.feeds.count) else {
            showPaywall = true
            return
        }

        guard let url = URL(string: manualURL) else {
            manualError = "Invalid URL"
            return
        }

        isAddingManual = true
        manualError = nil

        Task {
            let icon = await faviconService.resolveIcon(for: url)
            let title = manualTitle.isEmpty ? (url.host ?? "Feed") : manualTitle
            let feed = Feed(title: title, url: url, iconURL: icon)

            await MainActor.run {
                onAdd(feed)
                isAddingManual = false
                dismiss()
            }
        }
    }

    private func isAlreadySubscribed(_ result: FeedSearchResult) -> Bool {
        store.feeds.contains { $0.url == result.feedURL }
    }

    private func formatSubscribers(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
