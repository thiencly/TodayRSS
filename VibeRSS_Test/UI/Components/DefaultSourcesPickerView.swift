//
//  DefaultSourcesPickerView.swift
//  VibeRSS_Test
//
//  A reusable view for selecting default sources with individual source selection.
//  Used in onboarding and settings.
//

import SwiftUI

struct DefaultSourcesPickerView: View {
    @ObservedObject var store: FeedStore
    @Binding var isPresented: Bool
    let isOnboarding: Bool

    @State private var selectedSources: Set<URL> = []  // Track by URL for uniqueness
    @State private var expandedCategories: Set<UUID> = []
    @State private var isAdding = false
    @State private var showingPaywall = false

    private var isPremium: Bool {
        EntitlementManager.shared.isPremium
    }

    private var feedLimit: Int {
        EntitlementManager.shared.feedLimit
    }

    private var existingFeedCount: Int {
        store.feeds.count
    }

    private var totalSelectedCount: Int {
        selectedSources.count
    }

    private var remainingSlots: Int {
        max(0, feedLimit - existingFeedCount)
    }

    private var canSelectMore: Bool {
        isPremium || totalSelectedCount < remainingSlots
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with counter
                VStack(spacing: 8) {
                    if isOnboarding {
                        Text("Get Started")
                            .font(.system(size: 32, weight: .bold, design: .rounded))

                        Text("Select sources to add to your feed")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    // Source limit counter
                    if !isPremium {
                        HStack(spacing: 4) {
                            Image(systemName: "number.circle.fill")
                                .foregroundStyle(.blue)
                            Text("\(totalSelectedCount) of \(remainingSlots) sources selected")
                                .font(.subheadline.weight(.medium))
                            if existingFeedCount > 0 {
                                Text("(\(existingFeedCount) existing)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .padding(.top, 8)
                    }
                }
                .padding(.top, isOnboarding ? 20 : 12)
                .padding(.bottom, 16)

                // Category list with expandable sources
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(DefaultSources.categories) { category in
                            ExpandableCategoryRow(
                                category: category,
                                selectedSources: $selectedSources,
                                isExpanded: expandedCategories.contains(category.id),
                                canSelectMore: canSelectMore,
                                existingURLs: Set(store.feeds.map { $0.url }),
                                onToggleExpand: {
                                    HapticManager.shared.click()
                                    withAnimation(.snappy(duration: 0.25)) {
                                        if expandedCategories.contains(category.id) {
                                            expandedCategories.remove(category.id)
                                        } else {
                                            expandedCategories.insert(category.id)
                                        }
                                    }
                                },
                                onLimitReached: {
                                    HapticManager.shared.error()
                                    showingPaywall = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }

                // Bottom button
                VStack(spacing: 16) {
                    Button {
                        addSelectedSources()
                    } label: {
                        HStack {
                            if isAdding {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(buttonTitle)
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            selectedSources.isEmpty ? Color.gray : Color.blue
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(selectedSources.isEmpty || isAdding)

                    if isOnboarding {
                        Button {
                            isPresented = false
                        } label: {
                            Text("Skip for Now")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .navigationTitle(isOnboarding ? "" : "Add Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isOnboarding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(trigger: .feeds)
            }
        }
    }

    private var buttonTitle: String {
        if selectedSources.isEmpty {
            return "Select Sources"
        } else {
            return "Add \(selectedSources.count) Source\(selectedSources.count == 1 ? "" : "s")"
        }
    }

    private func addSelectedSources() {
        isAdding = true
        HapticManager.shared.success()

        // Group selected sources by their category for folder organization
        for category in DefaultSources.categories {
            let sourcesFromCategory = category.sources.filter { selectedSources.contains($0.url) }
            guard !sourcesFromCategory.isEmpty else { continue }

            // Find or create folder for this category
            let folder: Folder
            if let existingFolder = store.folders.first(where: { $0.name.lowercased() == category.name.lowercased() }) {
                folder = existingFolder
            } else {
                let newFolder = Folder(
                    name: category.name,
                    iconType: .sfSymbol(category.icon)
                )
                store.folders.append(newFolder)
                folder = newFolder
            }

            // Add sources to this folder
            for source in sourcesFromCategory {
                let alreadyExists = store.feeds.contains { $0.url == source.url }
                if !alreadyExists {
                    var feed = Feed(
                        title: source.title,
                        url: source.url,
                        iconURL: source.iconURL
                    )
                    feed.folderID = folder.id
                    store.feeds.append(feed)
                }
            }
        }

        // Dismiss after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isPresented = false
        }
    }
}

// MARK: - Expandable Category Row

private struct ExpandableCategoryRow: View {
    let category: SourceCategory
    @Binding var selectedSources: Set<URL>
    let isExpanded: Bool
    let canSelectMore: Bool
    let existingURLs: Set<URL>
    let onToggleExpand: () -> Void
    let onLimitReached: () -> Void

    private var selectedCountInCategory: Int {
        category.sources.filter { selectedSources.contains($0.url) }.count
    }

    private var availableSourcesInCategory: Int {
        category.sources.filter { !existingURLs.contains($0.url) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category header (tap to expand)
            Button(action: onToggleExpand) {
                HStack(spacing: 14) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(category.iconColor.opacity(0.15))
                            .frame(width: 48, height: 48)

                        Image(systemName: category.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(category.iconColor)
                    }

                    // Text
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("\(availableSourcesInCategory) sources available")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Selection count badge
                    if selectedCountInCategory > 0 {
                        Text("\(selectedCountInCategory)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.blue))
                    }

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
            .buttonStyle(.plain)

            // Expanded sources list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(category.sources) { source in
                        let isAlreadyAdded = existingURLs.contains(source.url)
                        let isSelected = selectedSources.contains(source.url)

                        SourceRow(
                            source: source,
                            isSelected: isSelected,
                            isDisabled: isAlreadyAdded,
                            disabledReason: isAlreadyAdded ? "Already added" : nil
                        ) {
                            if isAlreadyAdded { return }

                            HapticManager.shared.click()
                            if isSelected {
                                selectedSources.remove(source.url)
                            } else {
                                if canSelectMore {
                                    selectedSources.insert(source.url)
                                } else {
                                    onLimitReached()
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 32)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Individual Source Row

private struct SourceRow: View {
    let source: DefaultSource
    let isSelected: Bool
    let isDisabled: Bool
    let disabledReason: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Source icon placeholder
                ZStack {
                    Circle()
                        .fill(Color(.tertiarySystemGroupedBackground))
                        .frame(width: 36, height: 36)

                    Image(systemName: "doc.text")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // Source name
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(isDisabled ? .secondary : .primary)

                    if let reason = disabledReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : (isDisabled ? "checkmark.circle.fill" : "circle"))
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.blue : (isDisabled ? Color.green : Color.secondary.opacity(0.4)))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

#Preview {
    DefaultSourcesPickerView(
        store: FeedStore(),
        isPresented: .constant(true),
        isOnboarding: true
    )
}
