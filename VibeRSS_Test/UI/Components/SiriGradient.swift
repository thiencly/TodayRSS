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
    var cornerRadius: CGFloat = 22
    var opacity: Double = 0.35

    var body: some View {
        // Low frame rate (5fps) for subtle ambient animation with minimal CPU
        TimelineView(.animation(minimumInterval: 1.0 / 5.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let p = t.remainder(dividingBy: 12.0) / 12.0 // Slow 12s loop

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.clear)
                    .background(.clear)

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

// MARK: - Apple Intelligence Glow Colors
struct AppleIntelligenceColors {
    static let colors: [Color] = [
        Color(red: 0.74, green: 0.51, blue: 0.95),  // Purple #BC82F3
        Color(red: 0.96, green: 0.73, blue: 0.92),  // Pink #F5B9EA
        Color(red: 0.55, green: 0.62, blue: 1.0),   // Blue #8D9FFF
        Color(red: 0.67, green: 0.43, blue: 0.93),  // Violet #AA6EEE
        Color(red: 1.0, green: 0.40, blue: 0.47),   // Coral #FF6778
        Color(red: 1.0, green: 0.73, blue: 0.44),   // Orange #FFBA71
        Color(red: 0.78, green: 0.53, blue: 1.0),   // Light Purple #C686FF
    ]

    static func randomizedGradient() -> [Gradient.Stop] {
        let shuffled = colors.shuffled()
        var stops: [Gradient.Stop] = []
        for (index, color) in shuffled.enumerated() {
            let baseLocation = Double(index) / Double(shuffled.count)
            let jitter = Double.random(in: -0.08...0.08)
            let location = max(0, min(1, baseLocation + jitter))
            stops.append(Gradient.Stop(color: color, location: location))
        }
        return stops.sorted { $0.location < $1.location }
    }
}

// MARK: - Apple Intelligence Glow Effect
struct AppleIntelligenceGlow<S: InsettableShape>: View {
    let shape: S
    var isActive: Bool = false

    // Layer configuration: (lineWidth, blurRadius)
    private var activeLayers: [(CGFloat, CGFloat)] {
        [
            (3, 0),     // Sharp edge
            (5, 5),     // Close glow
            (8, 14),    // Mid glow
            (12, 26),   // Outer glow
            (16, 40),   // Far outer glow
        ]
    }

    var body: some View {
        // Wrap in Group so animation applies to the conditional content
        Group {
            if isActive {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let seconds = context.date.timeIntervalSinceReferenceDate
                    let currentPhase = (seconds.truncatingRemainder(dividingBy: 6.0) / 6.0) * 360.0

                    ZStack {
                        ForEach(activeLayers.indices.reversed(), id: \.self) { index in
                            let (lineWidth, blur) = activeLayers[index]
                            let layerOpacity = 0.7 * (0.6 + 0.1 * Double(index))

                            shape
                                .stroke(
                                    AngularGradient(
                                        colors: AppleIntelligenceColors.colors + [AppleIntelligenceColors.colors[0]],
                                        center: .center,
                                        startAngle: .degrees(currentPhase),
                                        endAngle: .degrees(currentPhase + 360)
                                    ),
                                    lineWidth: lineWidth
                                )
                                .blur(radius: blur)
                                .saturation(1.5)
                                .opacity(layerOpacity)
                                .blendMode(index == 0 ? .plusLighter : .screen)
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isActive)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Convenience initializers for common shapes
extension AppleIntelligenceGlow where S == Capsule {
    init(isActive: Bool = false) {
        self.shape = Capsule()
        self.isActive = isActive
    }
}

extension AppleIntelligenceGlow where S == RoundedRectangle {
    init(cornerRadius: CGFloat, isActive: Bool = false) {
        self.shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        self.isActive = isActive
    }
}
