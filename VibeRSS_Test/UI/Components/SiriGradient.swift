//
//  SiriGradient.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/27/25.
//


// SiriGradient.swift
// Provides the shared Siri-like gradient and a unified glow view modifier used across the app.
// Safe to use anywhere in SwiftUI views.

import SwiftUI

// MARK: - Shared Siri-like Gradient & Glow
struct SiriGradient {
    static let colors: [Color] = [
        Color.cyan, Color.blue, Color.indigo, Color.purple, Color.pink, Color.cyan
    ]

    static func linear(start: UnitPoint = .leading, end: UnitPoint = .trailing) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: start, endPoint: end)
    }

    static func angular(center: UnitPoint = .center, angle: Angle = .degrees(0)) -> AngularGradient {
        AngularGradient(colors: colors, center: .center, angle: angle)
    }
}

struct UnifiedGlowStyle: ViewModifier {
    var intensity: Double = 1.0
    func body(content: Content) -> some View {
        content
            .shadow(color: .blue.opacity(0.25 * intensity), radius: 6)
            .shadow(color: .purple.opacity(0.20 * intensity), radius: 10)
            .shadow(color: .pink.opacity(0.15 * intensity), radius: 14)
    }
}

extension View {
    func unifiedGlow(intensity: Double = 1.0) -> some View { self.modifier(UnifiedGlowStyle(intensity: intensity)) }
}

// A shared animation constant used by glow/gradient effects.
let unifiedAnimation: Animation = .linear(duration: 0.9).repeatForever(autoreverses: false)