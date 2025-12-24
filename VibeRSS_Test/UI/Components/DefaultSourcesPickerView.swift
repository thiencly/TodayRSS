//
//  DefaultSourcesPickerView.swift
//  VibeRSS_Test
//
//  A reusable view for selecting default source categories.
//  Used in onboarding and settings.
//

import SwiftUI

struct DefaultSourcesPickerView: View {
    @ObservedObject var store: FeedStore
    @Binding var isPresented: Bool
    let isOnboarding: Bool

    @State private var selectedCategories: Set<UUID> = []
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isOnboarding {
                    // Header for onboarding
                    VStack(spacing: 8) {
                        Text("Get Started")
                            .font(.system(size: 32, weight: .bold, design: .rounded))

                        Text("Select topics to add popular sources")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }

                // Category list
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(DefaultSources.categories) { category in
                            CategoryRow(
                                category: category,
                                isSelected: selectedCategories.contains(category.id)
                            ) {
                                toggleCategory(category)
                            }
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
                            selectedCategories.isEmpty ? Color.gray : Color.blue
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(selectedCategories.isEmpty || isAdding)

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
        }
    }

    private var buttonTitle: String {
        let count = selectedCategories.count
        if count == 0 {
            return "Select Topics"
        } else {
            let sourceCount = selectedCategories.reduce(0) { sum, categoryID in
                sum + (DefaultSources.categories.first { $0.id == categoryID }?.sources.count ?? 0)
            }
            return "Add \(sourceCount) Sources"
        }
    }

    private func toggleCategory(_ category: SourceCategory) {
        HapticManager.shared.click()
        if selectedCategories.contains(category.id) {
            selectedCategories.remove(category.id)
        } else {
            selectedCategories.insert(category.id)
        }
    }

    private func addSelectedSources() {
        isAdding = true
        HapticManager.shared.success()

        // Add sources organized by category/topic
        for categoryID in selectedCategories {
            if let category = DefaultSources.categories.first(where: { $0.id == categoryID }) {
                // Find or create folder for this category
                let folder: Folder
                if let existingFolder = store.folders.first(where: { $0.name.lowercased() == category.name.lowercased() }) {
                    folder = existingFolder
                } else {
                    // Create new folder with the category's icon
                    let newFolder = Folder(
                        name: category.name,
                        iconType: .sfSymbol(category.icon)
                    )
                    store.folders.append(newFolder)
                    folder = newFolder
                }

                // Add sources to this folder
                for source in category.sources {
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
        }

        // Dismiss after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isPresented = false
        }
    }
}

// MARK: - Category Row

private struct CategoryRow: View {
    let category: SourceCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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

                    Text("\(category.sources.count) sources")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Checkmark
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DefaultSourcesPickerView(
        store: FeedStore(),
        isPresented: .constant(true),
        isOnboarding: true
    )
}
