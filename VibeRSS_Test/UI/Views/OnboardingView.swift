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
            subtitle: "Your personal news reader with AI-powered summaries",
            features: []
        ),
        OnboardingPage(
            type: .features,
            title: "Add Your Sources",
            subtitle: "Subscribe to your favorite websites and blogs",
            features: [
                OnboardingFeature(
                    icon: "plus.circle.fill",
                    iconColor: .blue,
                    title: "Add RSS Feeds",
                    description: "Tap the + button to add news sources, blogs, and podcasts"
                ),
                OnboardingFeature(
                    icon: "globe",
                    iconColor: .cyan,
                    title: "Discover Content",
                    description: "Paste any website URL and we'll find the RSS feed for you"
                ),
                OnboardingFeature(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .green,
                    title: "Stay Updated",
                    description: "Your feeds sync automatically in the background"
                )
            ]
        ),
        OnboardingPage(
            type: .features,
            title: "Organize Your Way",
            subtitle: "Keep your feeds neat and tidy",
            features: [
                OnboardingFeature(
                    icon: "folder.fill",
                    iconColor: .orange,
                    title: "Create Folders",
                    description: "Group related sources into folders for easy access"
                ),
                OnboardingFeature(
                    icon: "hand.draw.fill",
                    iconColor: .purple,
                    title: "Drag & Drop",
                    description: "Long press and drag sources to organize them"
                ),
                OnboardingFeature(
                    icon: "star.fill",
                    iconColor: .yellow,
                    title: "Pin Favorites",
                    description: "Add sources to Today for quick highlights"
                )
            ]
        ),
        OnboardingPage(
            type: .features,
            title: "AI Summaries",
            subtitle: "Get the key points instantly",
            features: [
                OnboardingFeature(
                    icon: "sparkles",
                    iconColor: .purple,
                    title: "Quick Summaries",
                    description: "Tap the Summary button on any article for an AI-generated overview"
                ),
                OnboardingFeature(
                    icon: "brain.head.profile",
                    iconColor: .pink,
                    title: "On-Device AI",
                    description: "Summaries are generated privately on your device"
                ),
                OnboardingFeature(
                    icon: "slider.horizontal.3",
                    iconColor: .indigo,
                    title: "Adjustable Length",
                    description: "Choose between short or detailed summaries"
                )
            ]
        ),
        OnboardingPage(
            type: .features,
            title: "Today Highlights",
            subtitle: "Your personalized news at a glance",
            features: [
                OnboardingFeature(
                    icon: "rectangle.stack.fill",
                    iconColor: .blue,
                    title: "Highlights",
                    description: "See the latest from your favorite sources front and center"
                ),
                OnboardingFeature(
                    icon: "widget.small",
                    iconColor: .teal,
                    title: "Home Screen Widgets",
                    description: "Add widgets to see headlines without opening the app"
                ),
                OnboardingFeature(
                    icon: "bell.badge.fill",
                    iconColor: .red,
                    title: "New Article Badges",
                    description: "Blue dots show you what's new since your last visit"
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
                            .font(.headline)
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
                .frame(height: 60)

            // Title
            Text(page.title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            // Subtitle
            Text(page.subtitle)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 40)

            // Features
            VStack(spacing: 24) {
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
        HStack(alignment: .top, spacing: 16) {
            // Icon with background
            ZStack {
                Circle()
                    .fill(feature.iconColor.opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: feature.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(feature.iconColor)
            }

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.headline)

                Text(feature.description)
                    .font(.subheadline)
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
