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

// MARK: - Siri-like animated glow background
struct SiriGlow: View {
    @State private var phase: Double = 0
    var cornerRadius: CGFloat = 22
    var opacity: Double = 0.35

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let p = t.remainder(dividingBy: 6.0) / 6.0 // 6s loop

            ZStack {
                // Base soft blur background
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.clear)
                    .background(.clear)

                // Animated multi-color radial spots that drift slowly
                glowSpot(color: .purple, x: cos(2 * .pi * (p + 0.00)) * 0.35, y: sin(2 * .pi * (p + 0.00)) * 0.25, radius: 160)
                glowSpot(color: .blue,   x: cos(2 * .pi * (p + 0.33)) * 0.30, y: sin(2 * .pi * (p + 0.33)) * 0.30, radius: 170)
                glowSpot(color: .pink,   x: cos(2 * .pi * (p + 0.66)) * 0.25, y: sin(2 * .pi * (p + 0.66)) * 0.35, radius: 150)
            }
            .compositingGroup()
            .blur(radius: 40)
            .opacity(opacity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .drawingGroup()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glowSpot(color: Color, x: Double, y: Double, radius: CGFloat) -> some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let cx = w * 0.5 + CGFloat(x) * w * 0.6
            let cy = h * 0.5 + CGFloat(y) * h * 0.6
            Circle()
                .fill(
                    RadialGradient(colors: [color.opacity(0.8), color.opacity(0.0)], center: .center, startRadius: 0, endRadius: radius)
                )
                .frame(width: radius * 2, height: radius * 2)
                .position(x: cx, y: cy)
                .blendMode(.screen)
        }
    }
}
