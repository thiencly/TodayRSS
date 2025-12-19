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
    var showIdle: Bool = true  // Show subtle idle glow when not active
    var idleIntensity: Double = 1.0  // Multiplier for idle glow opacity
    var scale: CGFloat = 1.0  // Scale factor for glow size (0.5 = half size)

    // Layer configuration for active state: (lineWidth, blurRadius)
    private var activeLayers: [(CGFloat, CGFloat)] {
        [
            (3 * scale, 0),           // Sharp edge
            (5 * scale, 5 * scale),   // Close glow
            (8 * scale, 14 * scale),  // Mid glow
            (12 * scale, 26 * scale), // Outer glow
            (16 * scale, 40 * scale), // Far outer glow
        ]
    }

    var body: some View {
        ZStack {
            // Idle glow - single layer for scroll performance (was 3 layers)
            if showIdle && !isActive {
                shape
                    .stroke(
                        AngularGradient(
                            colors: AppleIntelligenceColors.colors + [AppleIntelligenceColors.colors[0]],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        lineWidth: 3 * scale
                    )
                    .blur(radius: 4 * scale)
                    .opacity(0.6 * idleIntensity)
                    .transition(.opacity)
            }

            // Active glow - fast, vibrant animation
            if isActive {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in  // 60fps for smooth active
                    let seconds = context.date.timeIntervalSinceReferenceDate
                    let currentPhase = (seconds.truncatingRemainder(dividingBy: 2.0) / 2.0) * 360.0  // 2s rotation

                    ZStack {
                        ForEach(activeLayers.indices.reversed(), id: \.self) { index in
                            let (lineWidth, blur) = activeLayers[index]
                            let layerOpacity = 0.6 * (0.6 + 0.1 * Double(index))  // Reduced for better color distinction

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

// MARK: - Priority Notification Glow (iOS 26 style)
// Animated moving gradient fill - optimized for scroll performance
struct PriorityNotificationGlow: View {
    var isActive: Bool = true
    var cornerRadius: CGFloat = 20

    @Environment(\.colorScheme) private var colorScheme

    // Static cache - randomized once per app launch, persists across view recreations
    // Uses all 7 Apple Intelligence colors for smoother, more varied gradient
    private static let cachedConfig: GlowConfig = {
        let shuffled = AppleIntelligenceColors.colors.shuffled()
        let offset = Double.random(in: 0..<100)
        return GlowConfig(colors: shuffled, phaseOffset: offset)
    }()

    private struct GlowConfig {
        let colors: [Color]
        let phaseOffset: Double
    }

    // Reduce intensity by 20% in dark mode
    private var glowOpacity: Double {
        colorScheme == .dark ? 0.4 : 0.5
    }

    var body: some View {
        if isActive {
            TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { context in
                let seconds = context.date.timeIntervalSinceReferenceDate + Self.cachedConfig.phaseOffset

                // Use sine wave for smooth back-and-forth motion (no jump at loop)
                let wave = sin(seconds * 0.3) * 0.5  // Slow oscillation between -0.5 and 0.5

                // Gradient moves smoothly back and forth
                LinearGradient(
                    colors: Self.cachedConfig.colors,
                    startPoint: UnitPoint(x: wave - 0.3, y: 0.2),
                    endPoint: UnitPoint(x: wave + 0.7, y: 0.8)
                )
                .blur(radius: 30)
                .opacity(glowOpacity)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .drawingGroup()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Convenience initializers for common shapes
extension AppleIntelligenceGlow where S == Capsule {
    init(isActive: Bool = false, showIdle: Bool = true, idleIntensity: Double = 1.0, scale: CGFloat = 1.0) {
        self.shape = Capsule()
        self.isActive = isActive
        self.showIdle = showIdle
        self.idleIntensity = idleIntensity
        self.scale = scale
    }
}

extension AppleIntelligenceGlow where S == RoundedRectangle {
    init(cornerRadius: CGFloat, isActive: Bool = false, showIdle: Bool = true, idleIntensity: Double = 1.0, scale: CGFloat = 1.0) {
        self.shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        self.isActive = isActive
        self.showIdle = showIdle
        self.idleIntensity = idleIntensity
        self.scale = scale
    }
}

// MARK: - Apple Mail-style AI Reveal Effect
// A gradient mask that sweeps from top to bottom, revealing content with an AI-colored edge

struct AIRevealEffect: ViewModifier {
    @Binding var isRevealed: Bool
    var duration: Double = 0.4
    var onComplete: (() -> Void)? = nil

    @State private var revealProgress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .mask(
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        // Revealed area (fully visible)
                        Rectangle()
                            .fill(Color.white)
                            .frame(height: geometry.size.height * revealProgress)

                        // Gradient edge with soft feather
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white.opacity(0.7), location: 0.4),
                                .init(color: .white.opacity(0.2), location: 0.7),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)

                        Spacer(minLength: 0)
                    }
                }
            )
            .overlay(
                // AI gradient glow at the reveal edge - more prominent
                GeometryReader { geometry in
                    if revealProgress > 0 && revealProgress < 1 {
                        ZStack {
                            // Outer glow
                            LinearGradient(
                                colors: AppleIntelligenceColors.colors + [AppleIntelligenceColors.colors[0]],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(height: 12)
                            .blur(radius: 8)
                            .opacity(0.6)

                            // Inner sharp line
                            LinearGradient(
                                colors: AppleIntelligenceColors.colors + [AppleIntelligenceColors.colors[0]],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(height: 3)
                            .blur(radius: 1)
                            .opacity(0.9)
                        }
                        .offset(y: geometry.size.height * revealProgress)
                    }
                }
                .allowsHitTesting(false)
            )
            .onChange(of: isRevealed) { _, newValue in
                if newValue {
                    withAnimation(.easeOut(duration: duration)) {
                        revealProgress = 1.0
                    }
                    // Call completion after animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                        onComplete?()
                    }
                } else {
                    revealProgress = 0
                }
            }
    }
}

extension View {
    func aiReveal(isRevealed: Binding<Bool>, duration: Double = 0.4, onComplete: (() -> Void)? = nil) -> some View {
        self.modifier(AIRevealEffect(isRevealed: isRevealed, duration: duration, onComplete: onComplete))
    }
}

// MARK: - AI Sweep Reveal (Single sweep from top to bottom, old fades as new reveals)
// One continuous gradient sweep that transforms old content to new content

struct AISweepReveal<OldContent: View, NewContent: View>: View {
    let oldContent: OldContent
    let newContent: NewContent
    @Binding var showNew: Bool
    var duration: Double = 0.5
    var onComplete: (() -> Void)? = nil

    @State private var revealProgress: CGFloat = 0

    init(
        showNew: Binding<Bool>,
        duration: Double = 0.5,
        onComplete: (() -> Void)? = nil,
        @ViewBuilder oldContent: () -> OldContent,
        @ViewBuilder newContent: () -> NewContent
    ) {
        self._showNew = showNew
        self.duration = duration
        self.onComplete = onComplete
        self.oldContent = oldContent()
        self.newContent = newContent()
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Old content - sharp cutoff, hidden after sweep
            if revealProgress < 1.0 {
                oldContent
                    .mask(
                        GeometryReader { geometry in
                            VStack(spacing: 0) {
                                // Hidden area - sharp cutoff at reveal line
                                Color.clear
                                    .frame(height: geometry.size.height * revealProgress)

                                // Remaining visible area
                                Color.white
                            }
                        }
                    )
            }

            // New content - sharp cutoff, revealed progressively
            newContent
                .mask(
                    GeometryReader { geometry in
                        VStack(spacing: 0) {
                            // Revealed area - sharp cutoff
                            Color.white
                                .frame(height: revealProgress >= 1.0 ? geometry.size.height : geometry.size.height * revealProgress)

                            if revealProgress < 1.0 {
                                Spacer(minLength: 0)
                            }
                        }
                    }
                )
        }
        // Rainbow gradient glow OUTSIDE the ZStack so it's not clipped
        .overlay(
            GeometryReader { geometry in
                if revealProgress > 0 && revealProgress < 1 {
                    ZStack {
                        // Outer soft glow
                        LinearGradient(
                            colors: AppleIntelligenceColors.colors + [AppleIntelligenceColors.colors[0]],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 30)
                        .blur(radius: 20)
                        .opacity(1.0)

                        // Inner bright line
                        LinearGradient(
                            colors: AppleIntelligenceColors.colors + [AppleIntelligenceColors.colors[0]],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 6)
                        .blur(radius: 2)
                        .opacity(1.0)
                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height * revealProgress)
                }
            }
            .allowsHitTesting(false)
        )
        .onChange(of: showNew) { _, newValue in
            if newValue {
                withAnimation(.easeOut(duration: duration)) {
                    revealProgress = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    onComplete?()
                }
            } else {
                // Reset instantly when going back
                revealProgress = 0
            }
        }
    }
}

// MARK: - AI Materialization Reveal (Liquid Glass style)
// Text materializes from a blurred, refracted state into sharp readable text

struct AIMaterializeReveal<OldContent: View, NewContent: View>: View {
    let oldContent: OldContent
    let newContent: NewContent
    @Binding var showNew: Bool
    var duration: Double = 0.6
    var onComplete: (() -> Void)? = nil

    @State private var materializeProgress: CGFloat = 0

    init(
        showNew: Binding<Bool>,
        duration: Double = 0.6,
        onComplete: (() -> Void)? = nil,
        @ViewBuilder oldContent: () -> OldContent,
        @ViewBuilder newContent: () -> NewContent
    ) {
        self._showNew = showNew
        self.duration = duration
        self.onComplete = onComplete
        self.oldContent = oldContent()
        self.newContent = newContent()
    }

    // Blur amount decreases as progress increases
    private var blurAmount: CGFloat {
        let maxBlur: CGFloat = 12
        return maxBlur * (1 - materializeProgress)
    }

    // Scale starts slightly larger and normalizes
    private var scaleAmount: CGFloat {
        let maxScale: CGFloat = 1.03
        return 1 + (maxScale - 1) * (1 - materializeProgress)
    }

    // Opacity increases with progress
    private var newOpacity: Double {
        return Double(materializeProgress)
    }

    // Old content fades out
    private var oldOpacity: Double {
        return Double(1 - materializeProgress)
    }

    var body: some View {
        ZStack {
            // Old content - fades out with slight blur
            if materializeProgress < 1.0 {
                oldContent
                    .blur(radius: materializeProgress * 4)
                    .opacity(oldOpacity)
            }

            // New content - materializes from blur
            if materializeProgress > 0 {
                newContent
                    .blur(radius: blurAmount)
                    .scaleEffect(scaleAmount)
                    .opacity(newOpacity)
            }
        }
        // Glass-like glow during materialization
        .overlay(
            GeometryReader { geometry in
                if materializeProgress > 0 && materializeProgress < 1 {
                    // Radial glow that expands during materialization
                    ZStack {
                        // Subtle rainbow glow
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                AngularGradient(
                                    colors: AppleIntelligenceColors.colors + [AppleIntelligenceColors.colors[0]],
                                    center: .center
                                ),
                                lineWidth: 3
                            )
                            .blur(radius: 8)
                            .opacity(0.5 * Double(1 - abs(materializeProgress - 0.5) * 2)) // Peak at 0.5

                        // Inner soft glow
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                RadialGradient(
                                    colors: [
                                        AppleIntelligenceColors.colors[0].opacity(0.15),
                                        AppleIntelligenceColors.colors[2].opacity(0.1),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: max(geometry.size.width, geometry.size.height) * 0.6
                                )
                            )
                            .opacity(Double(1 - abs(materializeProgress - 0.5) * 2)) // Peak at 0.5
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .allowsHitTesting(false)
        )
        .onChange(of: showNew) { _, newValue in
            if newValue {
                withAnimation(.easeOut(duration: duration)) {
                    materializeProgress = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    onComplete?()
                }
            } else {
                // Reset instantly
                materializeProgress = 0
            }
        }
    }
}

// MARK: - AI Sparkle Materialize (Enhanced version with sparkle particles)
// Individual text lines materialize with staggered timing and sparkle effects

struct AISparkleReveal<OldContent: View, NewContent: View>: View {
    let oldContent: OldContent
    let newContent: NewContent
    @Binding var showNew: Bool
    var duration: Double = 0.8
    var onComplete: (() -> Void)? = nil

    @State private var progress: CGFloat = 0
    @State private var sparklePhase: Double = 0

    init(
        showNew: Binding<Bool>,
        duration: Double = 0.8,
        onComplete: (() -> Void)? = nil,
        @ViewBuilder oldContent: () -> OldContent,
        @ViewBuilder newContent: () -> NewContent
    ) {
        self._showNew = showNew
        self.duration = duration
        self.onComplete = onComplete
        self.oldContent = oldContent()
        self.newContent = newContent()
    }

    var body: some View {
        ZStack {
            // Old content with dissolve effect
            if progress < 1.0 {
                oldContent
                    .blur(radius: progress * 6)
                    .opacity(Double(1 - progress))
                    .scaleEffect(1 - progress * 0.02)
            }

            // New content materializing
            if progress > 0 {
                newContent
                    .blur(radius: max(0, 8 - progress * 10))
                    .opacity(Double(min(1, progress * 1.5)))
                    .scaleEffect(1 + (1 - progress) * 0.02)
            }
        }
        // Sparkle overlay
        .overlay(
            GeometryReader { geometry in
                if progress > 0.1 && progress < 0.95 {
                    SparkleField(
                        size: geometry.size,
                        progress: progress,
                        phase: sparklePhase
                    )
                }
            }
            .allowsHitTesting(false)
        )
        .onChange(of: showNew) { _, newValue in
            if newValue {
                // Animate progress
                withAnimation(.easeInOut(duration: duration)) {
                    progress = 1.0
                }
                // Animate sparkle phase continuously during reveal
                withAnimation(.linear(duration: duration)) {
                    sparklePhase = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    onComplete?()
                }
            } else {
                progress = 0
                sparklePhase = 0
            }
        }
    }
}

// Sparkle particles that appear during materialization
private struct SparkleField: View {
    let size: CGSize
    let progress: CGFloat
    let phase: Double

    // Pre-computed sparkle positions
    private static let sparkles: [(x: CGFloat, y: CGFloat, delay: CGFloat, colorIndex: Int)] = {
        var result: [(CGFloat, CGFloat, CGFloat, Int)] = []
        for i in 0..<12 {
            result.append((
                x: CGFloat.random(in: 0.1...0.9),
                y: CGFloat.random(in: 0.1...0.9),
                delay: CGFloat.random(in: 0...0.6),
                colorIndex: Int.random(in: 0..<AppleIntelligenceColors.colors.count)
            ))
        }
        return result
    }()

    var body: some View {
        ZStack {
            ForEach(0..<Self.sparkles.count, id: \.self) { i in
                let sparkle = Self.sparkles[i]
                let adjustedProgress = max(0, min(1, (progress - sparkle.delay) / 0.4))
                let opacity = adjustedProgress > 0 && adjustedProgress < 1
                    ? sin(adjustedProgress * .pi) * 0.8
                    : 0

                Image(systemName: "sparkle")
                    .font(.system(size: 8 + adjustedProgress * 4))
                    .foregroundStyle(AppleIntelligenceColors.colors[sparkle.colorIndex])
                    .opacity(opacity)
                    .scaleEffect(0.5 + adjustedProgress * 0.5)
                    .position(
                        x: size.width * sparkle.x,
                        y: size.height * sparkle.y
                    )
            }
        }
    }
}

// MARK: - AI Blur-to-Focus Sweep (Option 6)
// A blur wave sweeps top to bottom, text sharpens as wave passes

struct AIBlurFocusReveal<OldContent: View, NewContent: View>: View {
    let oldContent: OldContent
    let newContent: NewContent
    @Binding var showNew: Bool
    var duration: Double = 0.7
    var onComplete: (() -> Void)? = nil

    @State private var sweepProgress: CGFloat = 0

    init(
        showNew: Binding<Bool>,
        duration: Double = 0.7,
        onComplete: (() -> Void)? = nil,
        @ViewBuilder oldContent: () -> OldContent,
        @ViewBuilder newContent: () -> NewContent
    ) {
        self._showNew = showNew
        self.duration = duration
        self.onComplete = onComplete
        self.oldContent = oldContent()
        self.newContent = newContent()
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Old content - blurs out and fades
            if sweepProgress < 1.0 {
                oldContent
                    .blur(radius: sweepProgress * 10)
                    .opacity(Double(1 - sweepProgress))
            }

            // New content - starts blurred, becomes sharp
            if sweepProgress > 0 {
                newContent
                    .blur(radius: max(0, 10 * (1 - sweepProgress)))
                    .opacity(Double(sweepProgress))
            }
        }
        // Rainbow glow during transition
        .overlay(
            GeometryReader { geometry in
                if sweepProgress > 0.05 && sweepProgress < 0.95 {
                    // Radial pulse glow that expands
                    let glowIntensity = sin(sweepProgress * .pi) // Peaks at 0.5

                    ZStack {
                        // Soft outer glow
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                AngularGradient(
                                    colors: AppleIntelligenceColors.colors + [AppleIntelligenceColors.colors[0]],
                                    center: .center
                                ),
                                lineWidth: 4
                            )
                            .blur(radius: 12)
                            .opacity(0.6 * glowIntensity)

                        // Inner glow
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        AppleIntelligenceColors.colors[0],
                                        AppleIntelligenceColors.colors[2],
                                        AppleIntelligenceColors.colors[4]
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                            .blur(radius: 4)
                            .opacity(0.4 * glowIntensity)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .allowsHitTesting(false)
        )
        .onChange(of: showNew) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: duration)) {
                    sweepProgress = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    onComplete?()
                }
            } else {
                sweepProgress = 0
            }
        }
    }
}

// MARK: - AI Cascade Reveal (Option 7 - Glass Morphing)
// Each article reveals one after another with a glass ripple effect

struct AICascadeReveal: View {
    @Binding var showNew: Bool
    var duration: Double = 0.9
    var itemCount: Int = 3
    var onComplete: (() -> Void)? = nil

    let oldItems: [AnyView]
    let newItems: [AnyView]

    @State private var revealedItems: Set<Int> = []
    @State private var itemProgress: [Int: CGFloat] = [:]

    init(
        showNew: Binding<Bool>,
        duration: Double = 0.9,
        onComplete: (() -> Void)? = nil,
        oldItems: [AnyView],
        newItems: [AnyView]
    ) {
        self._showNew = showNew
        self.duration = duration
        self.onComplete = onComplete
        self.oldItems = oldItems
        self.newItems = newItems
        self.itemCount = min(oldItems.count, newItems.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<itemCount, id: \.self) { index in
                ZStack {
                    // Old item
                    if !revealedItems.contains(index) || (itemProgress[index] ?? 0) < 1.0 {
                        oldItems[index]
                            .blur(radius: (itemProgress[index] ?? 0) * 8)
                            .opacity(1 - Double(itemProgress[index] ?? 0))
                            .scaleEffect(1 - (itemProgress[index] ?? 0) * 0.02)
                    }

                    // New item with glass morph effect
                    if revealedItems.contains(index) {
                        let progress = itemProgress[index] ?? 0
                        newItems[index]
                            .blur(radius: max(0, 12 * (1 - progress)))
                            .opacity(Double(progress))
                            .scaleEffect(1 + (1 - progress) * 0.05)
                            .overlay(
                                // Glass shimmer during reveal
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0),
                                                Color.white.opacity(0.3 * (1 - Double(progress))),
                                                Color.white.opacity(0)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .offset(x: (progress - 0.5) * 200)
                                    .blur(radius: 4)
                                    .opacity(progress > 0.1 && progress < 0.9 ? 1 : 0)
                            )
                            .clipped()
                    }
                }
                // Rainbow border glow when this item is actively revealing
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            AngularGradient(
                                colors: AppleIntelligenceColors.colors + [AppleIntelligenceColors.colors[0]],
                                center: .center
                            ),
                            lineWidth: 2
                        )
                        .blur(radius: 4)
                        .opacity(glowOpacity(for: index))
                )
            }
        }
        .onChange(of: showNew) { _, newValue in
            if newValue {
                startCascadeReveal()
            } else {
                resetReveal()
            }
        }
    }

    private func glowOpacity(for index: Int) -> Double {
        guard revealedItems.contains(index) else { return 0 }
        let progress = itemProgress[index] ?? 0
        // Peak glow at middle of animation
        return sin(Double(progress) * .pi) * 0.7
    }

    private func startCascadeReveal() {
        let staggerDelay = duration / Double(itemCount + 1)
        let itemDuration = duration * 0.6

        for index in 0..<itemCount {
            let delay = staggerDelay * Double(index)

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                revealedItems.insert(index)
                itemProgress[index] = 0

                withAnimation(.easeOut(duration: itemDuration)) {
                    itemProgress[index] = 1.0
                }
            }
        }

        // Call completion after all items revealed
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            onComplete?()
        }
    }

    private func resetReveal() {
        revealedItems.removeAll()
        itemProgress.removeAll()
    }
}

// MARK: - AI Downward Reveal with Rainbow Flash
// Old fades out, new reveals top-to-bottom, then angled rainbow colors sweep across text

struct AIDiagonalReveal<OldContent: View, NewContent: View>: View {
    let oldContent: OldContent
    let newContent: NewContent
    @Binding var showNew: Bool
    var fadeDuration: Double = 0.2
    var revealDuration: Double = 0.25
    var flashDuration: Double = 0.35
    var minHeight: CGFloat? = nil  // Minimum height for the content
    var onComplete: (() -> Void)? = nil

    @State private var phase: RevealPhase = .showingOld
    @State private var revealProgress: CGFloat = 0
    @State private var flashProgress: CGFloat = 0
    @State private var oldHeight: CGFloat = 0
    @State private var newHeight: CGFloat = 0
    @State private var currentHeight: CGFloat? = nil

    enum RevealPhase {
        case showingOld
        case fadingOut
        case revealing
        case flashing
        case done
    }

    init(
        showNew: Binding<Bool>,
        fadeDuration: Double = 0.2,
        revealDuration: Double = 0.25,
        flashDuration: Double = 0.35,
        minHeight: CGFloat? = nil,
        onComplete: (() -> Void)? = nil,
        @ViewBuilder oldContent: () -> OldContent,
        @ViewBuilder newContent: () -> NewContent
    ) {
        self._showNew = showNew
        self.fadeDuration = fadeDuration
        self.revealDuration = revealDuration
        self.flashDuration = flashDuration
        self.minHeight = minHeight
        self.onComplete = onComplete
        self.oldContent = oldContent()
        self.newContent = newContent()
    }

    // Effective height considering minimum
    private func effectiveHeight(_ measured: CGFloat) -> CGFloat {
        if let min = minHeight {
            return max(min, measured)
        }
        return measured
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Pre-measure new content height without affecting layout
            Color.clear
                .frame(height: 0)
                .overlay(
                    newContent
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { geo in
                            Color.clear
                                .onAppear { newHeight = geo.size.height }
                                .onChange(of: geo.size.height) { _, h in newHeight = h }
                        })
                        .opacity(0)
                        .allowsHitTesting(false)
                )

            // Visible content
            ZStack(alignment: .top) {
                // Old content - visible until fade out
                if phase == .showingOld || phase == .fadingOut {
                    oldContent
                        .background(GeometryReader { geo in
                            Color.clear.onAppear { oldHeight = geo.size.height }
                                .onChange(of: geo.size.height) { _, h in oldHeight = h }
                        })
                        .opacity(phase == .fadingOut ? 0 : 1)
                        .animation(.easeOut(duration: fadeDuration), value: phase)
                }

                // New content with top-to-bottom mask
                if phase == .revealing || phase == .flashing || phase == .done {
                    newContent
                        .mask(
                            GeometryReader { geometry in
                                VStack(spacing: 0) {
                                    // Revealed portion
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(height: geometry.size.height * revealProgress)
                                    Spacer(minLength: 0)
                                }
                            }
                        )
                        // Rainbow text coloring - wide gradient sweeps across and colors text
                        .overlay(
                            GeometryReader { geometry in
                                if phase == .flashing {
                                    // Wide rainbow gradient that lights up text as it passes
                                    let gradientWidth = geometry.size.width * 1.2
                                    let totalTravel = geometry.size.width + gradientWidth
                                    let xOffset = -gradientWidth + totalTravel * flashProgress

                                    LinearGradient(
                                        colors: [.clear] + AppleIntelligenceColors.colors + [.clear],
                                        startPoint: UnitPoint(x: 0, y: 0.3),
                                        endPoint: UnitPoint(x: 1, y: 0.7)
                                    )
                                    .frame(width: gradientWidth)
                                    .offset(x: xOffset)
                                    .blendMode(.sourceAtop)
                                }
                            }
                            .allowsHitTesting(false)
                        )
                        .compositingGroup()
                }
            }
            .frame(minHeight: minHeight, alignment: .top)
            .frame(height: currentHeight)
        }
        .onAppear {
            // Use minHeight as starting point, will update when oldHeight is measured
            if let min = minHeight {
                currentHeight = min
            }
        }
        .onChange(of: oldHeight) { _, newOldHeight in
            // Update current height when old content is measured (only if not transitioning)
            if phase == .showingOld {
                currentHeight = effectiveHeight(newOldHeight)
            }
        }
        .onChange(of: showNew) { _, newValue in
            if newValue {
                startRevealSequence()
            } else {
                resetReveal()
            }
        }
    }

    private func startRevealSequence() {
        // Phase 1: Fade out old content and animate height change
        phase = .fadingOut
        withAnimation(.easeInOut(duration: fadeDuration)) {
            currentHeight = effectiveHeight(newHeight)
        }

        // Phase 2: Start downward reveal after fade
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) {
            phase = .revealing
            revealProgress = 0
            withAnimation(.easeOut(duration: revealDuration)) {
                revealProgress = 1.0
            }
        }

        // Phase 3: Rainbow sweep - starts slightly before reveal finishes
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration + revealDuration * 0.5) {
            phase = .flashing
            flashProgress = 0
            withAnimation(.easeInOut(duration: flashDuration)) {
                flashProgress = 1.0
            }
        }

        // Phase 4: Done
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration + revealDuration * 0.5 + flashDuration) {
            phase = .done
            onComplete?()
        }
    }

    private func resetReveal() {
        withAnimation(.easeInOut(duration: fadeDuration)) {
            currentHeight = effectiveHeight(oldHeight)
        }
        phase = .showingOld
        revealProgress = 0
        flashProgress = 0
    }
}

// MARK: - Demo View for Testing AI Reveal Effect
struct AIRevealDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showNewSummaries: Bool = false
    @State private var selectedEffect: RevealEffect = .diagonal

    enum RevealEffect: String, CaseIterable {
        case diagonal = "Diagonal"
        case sweep = "Sweep"
        case cascade = "Cascade"
        case materialize = "Materialize"

        var description: String {
            switch self {
            case .diagonal: return "Fade out, diagonal reveal, rainbow flash"
            case .sweep: return "Rainbow gradient sweeps top to bottom"
            case .cascade: return "Articles reveal one by one with glass shimmer"
            case .materialize: return "All content blurs to focus together"
            }
        }
    }

    // Old summaries (what user sees initially)
    private let oldText1 = "Yesterday's news about tech industry layoffs affecting thousands of workers across major companies..."
    private let oldText2 = "Previous update on weather patterns showing mild temperatures expected throughout the week..."
    private let oldText3 = "Earlier market report indicating steady trading with no major changes in key indices..."

    // New summaries (what gets revealed)
    private let newText1 = "Apple announces new MacBook Pro with M4 chip, promising 2x faster performance and improved battery life for professional users."
    private let newText2 = "SpaceX successfully launches Starship on its fifth test flight, marking a major milestone in the company's Mars colonization plans."
    private let newText3 = "Federal Reserve signals potential rate cuts in 2025 as inflation continues to cool, markets respond positively to the news."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("AI Reveal Effects")
                        .font(.title2.bold())
                        .padding(.top, 20)

                    // Effect picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Effect")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        Picker("Effect", selection: $selectedEffect) {
                            ForEach(RevealEffect.allCases, id: \.self) { effect in
                                Text(effect.rawValue).tag(effect)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(selectedEffect.description)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 20)

                    // Demo card with selected effect
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedEffect {
                        case .diagonal:
                            AIDiagonalReveal(showNew: $showNewSummaries, minHeight: 220) {
                                oldContentView
                            } newContent: {
                                newContentView
                            }
                        case .sweep:
                            AISweepReveal(showNew: $showNewSummaries, duration: 0.7) {
                                oldContentView
                            } newContent: {
                                newContentView
                            }
                        case .cascade:
                            AICascadeReveal(
                                showNew: $showNewSummaries,
                                duration: 1.0,
                                oldItems: [
                                    AnyView(EntryRowView(iconColor: .blue, sourceName: "TechCrunch", summaryText: oldText1)),
                                    AnyView(EntryRowView(iconColor: .orange, sourceName: "Space News", summaryText: oldText2)),
                                    AnyView(EntryRowView(iconColor: .green, sourceName: "Bloomberg", summaryText: oldText3))
                                ],
                                newItems: [
                                    AnyView(EntryRowView(iconColor: .blue, sourceName: "TechCrunch", summaryText: newText1)),
                                    AnyView(EntryRowView(iconColor: .orange, sourceName: "Space News", summaryText: newText2)),
                                    AnyView(EntryRowView(iconColor: .green, sourceName: "Bloomberg", summaryText: newText3))
                                ]
                            )
                        case .materialize:
                            AIMaterializeReveal(showNew: $showNewSummaries, duration: 0.6) {
                                oldContentView
                            } newContent: {
                                newContentView
                            }
                        }
                    }
                    .padding(16)
                    .background {
                        PriorityNotificationGlow(isActive: true, cornerRadius: 20)
                    }
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 20)

                    Button(showNewSummaries ? "Reset to Old" : "Show New Summaries") {
                        showNewSummaries.toggle()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 20)

                    Spacer(minLength: 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: selectedEffect) { _, _ in
            // Reset when switching effects
            showNewSummaries = false
        }
    }

    private var oldContentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            EntryRowView(iconColor: .blue, sourceName: "TechCrunch", summaryText: oldText1)
            EntryRowView(iconColor: .orange, sourceName: "Space News", summaryText: oldText2)
            EntryRowView(iconColor: .green, sourceName: "Bloomberg", summaryText: oldText3)
        }
    }

    private var newContentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            EntryRowView(iconColor: .blue, sourceName: "TechCrunch", summaryText: newText1)
            EntryRowView(iconColor: .orange, sourceName: "Space News", summaryText: newText2)
            EntryRowView(iconColor: .green, sourceName: "Bloomberg", summaryText: newText3)
        }
    }
}

// Simple entry row for demo
private struct EntryRowView: View {
    let iconColor: Color
    let sourceName: String
    let summaryText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(iconColor).frame(width: 20, height: 20)
                Text(sourceName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            Text(summaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2...3)  // Minimum 2 lines, max 3 lines
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)  // ~2 lines minimum
        }
    }
}

#Preview {
    AIRevealDemoView()
}
