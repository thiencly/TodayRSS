//
//  OnboardingView.swift
//  VibeRSS_Test
//
//  Apple-style onboarding for new users
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            type: .welcome,
            title: "Welcome to\nTodayRSS",
            subtitle: "Your personal news reader with AI-powered summaries, beautiful widgets, and seamless sync across all your devices",
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
                        OnboardingPageView(page: pages[index])
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
    }

    private func completeOnboarding() {
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

    var body: some View {
        VStack(spacing: 0) {
            if page.type == .welcome {
                welcomeContent
            } else {
                featuresContent
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
