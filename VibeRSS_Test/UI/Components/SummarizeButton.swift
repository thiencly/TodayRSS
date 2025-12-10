//
//  SummarizeButton.swift
//  Extracted UI component for the summarization control button with glow overlay.
//  Purpose: Reusable SwiftUI control that displays "Summarize" / "Summary", shows generating state,
//  and renders a Siri-like rotating glow. This file contains no app-specific view models.
//
//  Dependencies: SwiftUI, SiriGradient (colors) and GlassPillStyle (style) defined elsewhere.
//

import SwiftUI

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
    // Each button gets a random color from the AI palette for rainbow variety
    @State private var sparkleColor: Color = AppleIntelligenceColors.colors.randomElement() ?? .purple

    // Apple Intelligence glow overlay - only show when generating
    @ViewBuilder
    private func rotatingGlowOverlay() -> some View {
        AppleIntelligenceGlow<Capsule>(isActive: isGenerating, showIdle: false)
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
        Button {
            HapticManager.shared.lightTap()
            action()
        } label: {
            HStack(spacing: 4) {
                Group {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        // Random AI color per button - creates rainbow variety without gradient cost
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(sparkleColor)
                            .frame(width: 16, height: 16)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: isGenerating)

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
            .frame(minWidth: 110, minHeight: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(GlassPillStyle())
        .background(
            // Base glass material
            Capsule()
                .fill(.thinMaterial)
        )
        // Siri-like glow halo placed outside clipping so it's visible
        .overlay(
            rotatingGlowOverlay()
        )
        .overlay(
            chromeOverlays()
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        .scaleEffect(isGenerating ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.35), value: isGenerating)
        .accessibilityLabel(title)
    }
}

// MARK: - Liquid Glass version of SummarizeButton
// To use this version, replace SummarizeButton with SummarizeButtonLiquidGlass in ArticleRowView
struct SummarizeButtonLiquidGlass: View {
    enum ButtonState {
        case none
        case generating
        case hasSummary(isExpanded: Bool)
    }

    var state: ButtonState
    var action: () -> Void

    // Visual state
    @State private var pulse = false
    // Each button gets a random color from the AI palette for rainbow variety
    @State private var sparkleColor: Color = AppleIntelligenceColors.colors.randomElement() ?? .purple

    // Apple Intelligence glow overlay - only show when generating (reduced size to avoid clipping)
    @ViewBuilder
    private func rotatingGlowOverlay() -> some View {
        AppleIntelligenceGlow<Capsule>(isActive: isGenerating, showIdle: false, scale: 0.4)
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
        Button {
            HapticManager.shared.lightTap()
            action()
        } label: {
            HStack(spacing: 4) {
                Group {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        // Random AI color per button - creates rainbow variety without gradient cost
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(sparkleColor)
                            .frame(width: 16, height: 16)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: isGenerating)

                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)

                Image(systemName: showChevron ? "chevron.down" : "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .frame(width: 12, height: 12, alignment: .center)
                    .rotationEffect(.degrees(showChevron && isExpanded ? -180 : 0))
                    .animation(.easeInOut(duration: 0.25), value: isExpanded)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minWidth: 110, minHeight: 34)
            .glassEffect(.regular.interactive())
            .overlay(
                rotatingGlowOverlay()
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isGenerating ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.35), value: isGenerating)
        .accessibilityLabel(title)
    }
}
