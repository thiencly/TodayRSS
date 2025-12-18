//
//  RoundedFonts.swift
//  VibeRSS_Test
//
//  SF Pro Rounded font helpers for titles
//

import SwiftUI

// MARK: - Rounded Title Fonts

extension Font {
    /// Large title with SF Pro Rounded
    static var roundedLargeTitle: Font {
        .system(.largeTitle, design: .rounded)
    }

    /// Title with SF Pro Rounded
    static var roundedTitle: Font {
        .system(.title, design: .rounded)
    }

    /// Title 2 with SF Pro Rounded
    static var roundedTitle2: Font {
        .system(.title2, design: .rounded)
    }

    /// Title 3 with SF Pro Rounded
    static var roundedTitle3: Font {
        .system(.title3, design: .rounded)
    }

    /// Headline with SF Pro Rounded
    static var roundedHeadline: Font {
        .system(.headline, design: .rounded)
    }

    /// Custom rounded font with specific size and weight
    static func rounded(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - View Modifier for Rounded Titles

struct RoundedTitleStyle: ViewModifier {
    let size: Font.TextStyle
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content
            .font(.system(size, design: .rounded, weight: weight))
    }
}

extension View {
    /// Apply rounded title style
    func roundedTitle(_ size: Font.TextStyle = .title, weight: Font.Weight = .bold) -> some View {
        modifier(RoundedTitleStyle(size: size, weight: weight))
    }
}

// MARK: - Navigation Bar Appearance Setup

enum AppAppearance {
    /// Configure navigation bar to use SF Pro Rounded for titles
    static func setupNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()

        // Large title attributes - SF Pro Rounded Bold
        if let roundedFont = UIFont(name: "SFProRounded-Bold", size: 34) {
            appearance.largeTitleTextAttributes = [.font: roundedFont]
        } else {
            // Fallback to system rounded
            let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
                .withDesign(.rounded)?
                .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold]])
            if let descriptor = descriptor {
                appearance.largeTitleTextAttributes = [.font: UIFont(descriptor: descriptor, size: 34)]
            }
        }

        // Standard title attributes - SF Pro Rounded Semibold
        if let roundedFont = UIFont(name: "SFProRounded-Semibold", size: 17) {
            appearance.titleTextAttributes = [.font: roundedFont]
        } else {
            // Fallback to system rounded
            let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline)
                .withDesign(.rounded)?
                .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]])
            if let descriptor = descriptor {
                appearance.titleTextAttributes = [.font: UIFont(descriptor: descriptor, size: 17)]
            }
        }

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}
