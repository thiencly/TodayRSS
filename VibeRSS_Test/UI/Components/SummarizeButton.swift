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

    // iOS 18 Siri-style glow overlay with multi-layered bleeding glow
    @ViewBuilder
    private func rotatingGlowOverlay() -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate

            // Idle: slow rotation, subtle glow. Working: fast rotation, intense glow
            let rotationPeriod: Double = isGenerating ? 1.5 : 6.0
            let rotation = Angle(degrees: (seconds.truncatingRemainder(dividingBy: rotationPeriod) / rotationPeriod) * 360.0)

            // Breathing pulse animation (slower cycle)
            let pulsePeriod: Double = isGenerating ? 1.2 : 3.0
            let pulsePhase = seconds.truncatingRemainder(dividingBy: pulsePeriod) / pulsePeriod
            let pulseScale = 1.0 + sin(pulsePhase * 2 * .pi) * (isGenerating ? 0.2 : 0.08)

            // State-dependent glow intensity - working state is MUCH brighter
            let glowIntensity: Double = isGenerating ? 2.5 : 0.3
            let glowSaturation: Double = isGenerating ? 2.2 : 1.3

            ZStack {
                // Outer diffuse glow (bleeds far outside)
                Capsule()
                    .fill(
                        AngularGradient(
                            colors: SiriGradient.colors,
                            center: .center,
                            angle: .degrees(0)
                        )
                    )
                    .saturation(glowSaturation)
                    .blur(radius: isGenerating ? 100 : 45)
                    .opacity(glowIntensity * 0.5)
                    .scaleEffect(pulseScale * (isGenerating ? 1.45 : 1.15))
                    .blendMode(.screen)

                // Mid-range glow layer
                Capsule()
                    .fill(
                        AngularGradient(
                            colors: SiriGradient.colors,
                            center: .center,
                            angle: .degrees(0)
                        )
                    )
                    .saturation(glowSaturation)
                    .blur(radius: isGenerating ? 65 : 28)
                    .opacity(glowIntensity * 0.7)
                    .scaleEffect(pulseScale * (isGenerating ? 1.28 : 1.1))
                    .blendMode(.screen)

                // Close glow layer
                Capsule()
                    .strokeBorder(
                        AngularGradient(
                            colors: SiriGradient.colors,
                            center: .center,
                            angle: .degrees(0)
                        ),
                        lineWidth: 4
                    )
                    .saturation(glowSaturation)
                    .blur(radius: isGenerating ? 38 : 16)
                    .opacity(glowIntensity * 0.9)
                    .scaleEffect(pulseScale * 1.05)
                    .blendMode(.screen)

                // Sharp edge highlight
                Capsule()
                    .strokeBorder(
                        AngularGradient(
                            colors: SiriGradient.colors,
                            center: .center,
                            angle: .degrees(0)
                        ),
                        lineWidth: 2.5
                    )
                    .saturation(glowSaturation * 1.15)
                    .blur(radius: isGenerating ? 12 : 4)
                    .opacity(glowIntensity)
                    .blendMode(.plusLighter)
            }
            .rotationEffect(rotation)
            .padding(-40) // Allow glow to extend beyond border
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.7), value: isGenerating)
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
        .scaleEffect(isGenerating ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.5), value: isGenerating)
        .accessibilityLabel(title)
    }
}

