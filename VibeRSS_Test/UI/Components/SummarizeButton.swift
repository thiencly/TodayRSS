//
//  SummarizeButton.swift
//  Extracted UI component for the summarization control button with glow overlay.
//  Purpose: Reusable SwiftUI control that displays "Summarize" / "Summary", shows generating state,
//  and renders a Siri-like rotating glow. This file contains no app-specific view models.
//
//  Dependencies: SwiftUI, SiriGradient (colors) and GlassPillStyle (style) defined elsewhere.
//

import SwiftUI

// MARK: - Siri-like rotating glow overlay used by SummarizeButton
private struct SpinningSmokeyGlow: View {
    var pulse: Bool

    // A rotating angular gradient ring that sits on the button border
    private func ring(angle: Angle) -> some View {
        Capsule()
            .strokeBorder(
                AngularGradient(
                    colors: SiriGradient.colors,
                    center: .center,
                    angle: angle
                ),
                lineWidth: 3
            )
            .opacity(0.9)
    }

    // Soft smoky wisps that extend beyond the border
    private func smoke(angle: Angle) -> some View {
        ZStack {
            Capsule()
                .fill(AngularGradient(colors: SiriGradient.colors, center: .center, angle: angle))
                .opacity(0.42)
                .blur(radius: 30)
                .scaleEffect(pulse ? 1.14 : 1.08)

            Capsule()
                .fill(AngularGradient(colors: SiriGradient.colors, center: .center, angle: angle))
                .opacity(0.26)
                .blur(radius: 48)
                .scaleEffect(pulse ? 1.22 : 1.14)

            Capsule()
                .fill(AngularGradient(colors: SiriGradient.colors, center: .center, angle: angle))
                .opacity(0.16)
                .blur(radius: 72)
                .scaleEffect(pulse ? 1.32 : 1.22)
        }
        .padding(-26)
    }

    var body: some View {
        // Drive rotation continuously with TimelineView so it won't stall on state changes
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            // 8 seconds per full rotation for a calm motion
            let seconds = context.date.timeIntervalSinceReferenceDate
            let progress = seconds.truncatingRemainder(dividingBy: 8.0) / 8.0
            let angle = Angle(degrees: progress * 360.0)

            ZStack {
                smoke(angle: .degrees(0))
                ring(angle: .degrees(0))
            }
            .rotationEffect(angle)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Public SummarizeButton component
struct SummarizeButton: View {
    enum ButtonState {
        case none
        case generating
        case hasSummary(isExpanded: Bool)
    }

    var state: ButtonState
    var action: () -> Void

    // Visual state
    @State private var pulse = false

    // Rotating glow overlay
    @ViewBuilder
    private func rotatingGlowOverlay() -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            // Faster spin when idle, slightly slower when generating to reduce distraction
            let period: Double = isGenerating ? 2.0 : 6.0 // seconds per full rotation
            // Brighter glow when idle
            let baseGlowOpacity: Double = isGenerating ? 3 : 0.5
            let blurFill: CGFloat = isGenerating ? 58 : 52
            let blur1: CGFloat = isGenerating ? 44 : 40
            let blur2: CGFloat = isGenerating ? 84 : 76
            let saturationBoost: Double = isGenerating ? 1.55 : 1.35

            let rotation = Angle(degrees: (seconds.truncatingRemainder(dividingBy: period) / period) * 360.0)

            ZStack {
                Capsule()
                    .fill(
                        AngularGradient(colors: SiriGradient.colors, center: .center, angle: .degrees(0))
                    )
                    .saturation(saturationBoost)
                    .opacity(baseGlowOpacity * 0.55)
                    .blur(radius: blurFill)
                    .blendMode(.plusLighter)

                Capsule()
                    .strokeBorder(
                        AngularGradient(colors: SiriGradient.colors, center: .center, angle: .degrees(0)),
                        lineWidth: 3
                    )
                    .saturation(saturationBoost)
                    .opacity(baseGlowOpacity)
                    .blur(radius: blur1)
                    .blendMode(.plusLighter)

                Capsule()
                    .strokeBorder(
                        AngularGradient(colors: SiriGradient.colors, center: .center, angle: .degrees(0)),
                        lineWidth: 2
                    )
                    .saturation(saturationBoost)
                    .opacity(baseGlowOpacity * 0.9)
                    .blur(radius: blur2)
                    .blendMode(.plusLighter)
            }
            .rotationEffect(rotation)
            .padding(-22)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func chromeOverlays() -> some View {
        ZStack {
            Capsule()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                .blendMode(.overlay)
            Capsule()
                .strokeBorder(Color.secondary.opacity(0.20), lineWidth: 1)
        }
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(colors: [
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.15),
                        .clear
                    ], startPoint: .top, endPoint: .bottom), lineWidth: 1
                )
                .opacity(0.75)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(colors: [
                        .clear,
                        Color.black.opacity(0.10)
                    ], startPoint: .top, endPoint: .bottom), lineWidth: 1
                )
        )
    }

    private var title: String { "Summary" }

    private var isGenerating: Bool {
        if case .generating = state { return true }
        return false
    }

    private var showChevron: Bool {
        if case .hasSummary = state { return true }
        return false
    }

    private var isExpanded: Bool {
        if case let .hasSummary(expanded) = state { return expanded }
        return false
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Group {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                            .transition(.opacity)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 16, height: 16)
                            .scaleEffect(1.0)
                    }
                }

                Text(title)
                    .font(.callout.weight(.semibold))

                Group {
                    if showChevron {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 12, height: 12, alignment: .center)
                    } else {
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .opacity(1.0)
                            .frame(width: 12, height: 12, alignment: .center)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(minWidth: 110)
            .contentShape(Capsule())
        }
        .buttonStyle(GlassPillStyle())
        .background(
            // Base glass material
            Capsule()
                .fill(.thinMaterial)
        )
        // Siri-like glow halo placed outside clipping so it’s visible
        .overlay(
            rotatingGlowOverlay()
        )
        .overlay(
            chromeOverlays()
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        .scaleEffect(isGenerating ? 1.01 : 1.0)
        .animation(isGenerating ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: isGenerating)
        .accessibilityLabel(title)
    }
}

