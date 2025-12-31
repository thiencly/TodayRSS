//
//  OnboardingView.swift
//  VibeRSS_Test
//
//  Apple-style onboarding for new users
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @ObservedObject var store: FeedStore
    @State private var currentPage = 0
    @State private var selectedSources: Set<URL> = []  // Track individual sources by URL
    @State private var expandedCategories: Set<UUID> = []
    @State private var isAddingSources = false
    @State private var showingPaywall = false

    init(isPresented: Binding<Bool>, store: FeedStore? = nil) {
        self._isPresented = isPresented
        self.store = store ?? FeedStore()
    }

    private var isPremium: Bool {
        EntitlementManager.shared.isPremium
    }

    private var feedLimit: Int {
        EntitlementManager.shared.feedLimit
    }

    private var canSelectMore: Bool {
        isPremium || selectedSources.count < feedLimit
    }

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            type: .welcome,
            title: "Welcome to\nTodayRSS",
            subtitle: "Your personal RSS feed with no algorithm, AI-powered summaries, and swipeable News Reel.",
            features: []
        ),
        OnboardingPage(
            type: .features,
            title: "Smart Reading",
            subtitle: "Powerful ways to consume your news",
            features: [
                OnboardingFeature(
                    icon: "sparkles",
                    iconColor: .purple,
                    title: "AI Summaries",
                    description: "Get instant summaries of any article, powered by on-device AI for complete privacy"
                ),
                OnboardingFeature(
                    icon: "rectangle.stack.fill",
                    iconColor: .pink,
                    title: "News Reel",
                    description: "Swipe through articles with auto-generated summaries, like a news feed made just for you"
                ),
                OnboardingFeature(
                    icon: "square.text.square.fill",
                    iconColor: .blue,
                    title: "At a Glance",
                    description: "See the latest headlines from all your sources in one expandable card"
                ),
                OnboardingFeature(
                    icon: "heart.fill",
                    iconColor: .red,
                    title: "Save for Later",
                    description: "Bookmark articles to read when you have more time"
                )
            ]
        ),
        OnboardingPage(
            type: .features,
            title: "Stay Organized",
            subtitle: "Your news, your way",
            features: [
                OnboardingFeature(
                    icon: "folder.fill",
                    iconColor: .orange,
                    title: "Topics & Folders",
                    description: "Group your sources into topics and pin your favorites for the News Reel"
                ),
                OnboardingFeature(
                    icon: "widget.medium",
                    iconColor: .teal,
                    title: "Home Screen Widgets",
                    description: "Add beautiful widgets to see headlines without opening the app"
                ),
                OnboardingFeature(
                    icon: "icloud.fill",
                    iconColor: .cyan,
                    title: "iCloud Sync",
                    description: "Your feeds and settings sync automatically across all your Apple devices"
                ),
                OnboardingFeature(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .green,
                    title: "Background Updates",
                    description: "Feeds refresh automatically so you always have the latest news"
                )
            ]
        ),
        OnboardingPage(
            type: .sources,
            title: "Add Sources",
            subtitle: "Select topics to get started with popular sources",
            features: []
        )
    ]

    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingPageView(
                            page: pages[index],
                            selectedSources: pages[index].type == .sources ? $selectedSources : nil,
                            expandedCategories: pages[index].type == .sources ? $expandedCategories : nil,
                            isPremium: isPremium,
                            feedLimit: feedLimit,
                            canSelectMore: canSelectMore,
                            onLimitReached: {
                                HapticManager.shared.error()
                                showingPaywall = true
                            }
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // Bottom section
                VStack(spacing: 20) {
                    // Page indicators
                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? Color.primary : Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                                .scaleEffect(index == currentPage ? 1.2 : 1.0)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }
                    .padding(.bottom, 10)

                    // Continue button
                    Button {
                        if currentPage < pages.count - 1 {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                currentPage += 1
                            }
                        } else {
                            completeOnboarding()
                        }
                    } label: {
                        Text(currentPage < pages.count - 1 ? "Continue" : "Get Started")
                            .font(.roundedHeadline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 24)

                    // Skip button (only show if not on last page)
                    if currentPage < pages.count - 1 {
                        Button {
                            completeOnboarding()
                        } label: {
                            Text("Skip")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        // Placeholder to maintain layout
                        Text(" ")
                            .font(.subheadline)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(trigger: .feeds)
        }
    }

    private func completeOnboarding() {
        // Add selected sources to the store, organized by topic
        for category in DefaultSources.categories {
            let sourcesFromCategory = category.sources.filter { selectedSources.contains($0.url) }
            guard !sourcesFromCategory.isEmpty else { continue }

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

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        withAnimation(.easeOut(duration: 0.3)) {
            isPresented = false
        }
    }
}

// MARK: - Data Models

struct OnboardingPage {
    enum PageType {
        case welcome
        case features
        case sources
    }

    let type: PageType
    let title: String
    let subtitle: String
    let features: [OnboardingFeature]
}

struct OnboardingFeature {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
}

// MARK: - Page View

struct OnboardingPageView: View {
    let page: OnboardingPage
    var selectedSources: Binding<Set<URL>>?
    var expandedCategories: Binding<Set<UUID>>?
    var isPremium: Bool = false
    var feedLimit: Int = 5
    var canSelectMore: Bool = true
    var onLimitReached: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            switch page.type {
            case .welcome:
                welcomeContent
            case .features:
                featuresContent
            case .sources:
                if let sourcesBinding = selectedSources,
                   let expandedBinding = expandedCategories {
                    sourcesContent(
                        selectedSources: sourcesBinding,
                        expandedCategories: expandedBinding
                    )
                }
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var welcomeContent: some View {
        Spacer()

        // App icon with glow
        ZStack {
            // Glow effect
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.orange, .pink, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 140, height: 140)
                .blur(radius: 40)
                .opacity(0.6)

            // Icon background
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.6, blue: 0.4),
                            Color(red: 1.0, green: 0.4, blue: 0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)

            // Icon
            Image(systemName: "newspaper.fill")
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.bottom, 50)

        // Title
        Text(page.title)
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .padding(.bottom, 16)

        // Subtitle
        Text(page.subtitle)
            .font(.title3)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)

        Spacer()
        Spacer()
    }

    @ViewBuilder
    private var featuresContent: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 40)

            // Title
            Text(page.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)

            // Subtitle
            Text(page.subtitle)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)

            // Features - compact spacing for 4 items
            VStack(spacing: 18) {
                ForEach(page.features.indices, id: \.self) { index in
                    FeatureRow(feature: page.features[index])
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func sourcesContent(
        selectedSources: Binding<Set<URL>>,
        expandedCategories: Binding<Set<UUID>>
    ) -> some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 10)

            // Title
            Text(page.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)

            // Subtitle
            Text(page.subtitle)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            // Source limit counter for free users
            if !isPremium {
                HStack(spacing: 4) {
                    Image(systemName: "number.circle.fill")
                        .foregroundStyle(.blue)
                    Text("\(selectedSources.wrappedValue.count) of \(feedLimit) sources selected")
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .padding(.bottom, 12)
            }

            // Category picker with expandable sources
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(DefaultSources.categories) { category in
                        OnboardingExpandableCategoryRow(
                            category: category,
                            selectedSources: selectedSources,
                            isExpanded: expandedCategories.wrappedValue.contains(category.id),
                            canSelectMore: canSelectMore,
                            onToggleExpand: {
                                HapticManager.shared.click()
                                withAnimation(.snappy(duration: 0.25)) {
                                    if expandedCategories.wrappedValue.contains(category.id) {
                                        expandedCategories.wrappedValue.remove(category.id)
                                    } else {
                                        expandedCategories.wrappedValue.insert(category.id)
                                    }
                                }
                            },
                            onLimitReached: onLimitReached ?? {}
                        )
                    }
                }
            }

            Spacer()
                .frame(height: 10)
        }
    }
}

// MARK: - Expandable Category Row (for Onboarding)

private struct OnboardingExpandableCategoryRow: View {
    let category: SourceCategory
    @Binding var selectedSources: Set<URL>
    let isExpanded: Bool
    let canSelectMore: Bool
    let onToggleExpand: () -> Void
    let onLimitReached: () -> Void

    private var selectedCountInCategory: Int {
        category.sources.filter { selectedSources.contains($0.url) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category header (tap to expand)
            Button(action: onToggleExpand) {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(category.iconColor.opacity(0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: category.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(category.iconColor)
                    }

                    // Text
                    VStack(alignment: .leading, spacing: 1) {
                        Text(category.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)

                        Text("\(category.sources.count) sources")
                            .font(.caption)
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
            .buttonStyle(.plain)

            // Expanded sources list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(category.sources) { source in
                        let isSelected = selectedSources.contains(source.url)

                        OnboardingSourceRow(
                            source: source,
                            isSelected: isSelected
                        ) {
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
                .padding(.leading, 28)
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Individual Source Row (for Onboarding)

private struct OnboardingSourceRow: View {
    let source: DefaultSource
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Source icon placeholder
                ZStack {
                    Circle()
                        .fill(Color(.tertiarySystemGroupedBackground))
                        .frame(width: 32, height: 32)

                    Image(systemName: "doc.text")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // Source name
                Text(source.title)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                Spacer()

                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.4))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let feature: OnboardingFeature

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Icon with background
            ZStack {
                Circle()
                    .fill(feature.iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: feature.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(feature.iconColor)
            }

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))

                Text(feature.description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(isPresented: .constant(true))
}
