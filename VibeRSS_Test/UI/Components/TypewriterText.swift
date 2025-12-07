//
//  GradientRevealText.swift
//  VibeRSS_Test
//
//  Text that appears with a rainbow gradient overlay that fades away.
//

import SwiftUI

/// Text that appears with a rainbow gradient overlay that fades to normal color.
struct GradientRevealText: View {
    let text: String
    var font: Font = .footnote
    var foregroundStyle: Color = .secondary
    var gradientDuration: Double = 1.2
    var onComplete: (() -> Void)? = nil

    @State private var showGradient: Bool = true
    @State private var gradientOpacity: Double = 1.0
    @State private var gradientPhase: CGFloat = 0
    @State private var hasStarted: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Base text (always visible)
            Text(text)
                .font(font)
                .foregroundStyle(foregroundStyle)
                .lineLimit(3)

            // Rainbow gradient overlay that fades out
            if showGradient {
                Text(text)
                    .font(font)
                    .foregroundStyle(.clear)
                    .lineLimit(3)
                    .overlay {
                        LinearGradient(
                            colors: AppleIntelligenceColors.colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .hueRotation(.degrees(gradientPhase))
                        .mask(
                            Text(text)
                                .font(font)
                                .lineLimit(3)
                        )
                    }
                    .shadow(color: .purple.opacity(0.5 * gradientOpacity), radius: 6)
                    .shadow(color: .cyan.opacity(0.4 * gradientOpacity), radius: 10)
                    .opacity(gradientOpacity)
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        guard !hasStarted else { return }
        hasStarted = true

        // Animate gradient hue rotation
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            gradientPhase = 360
        }

        // Fade out the gradient overlay
        withAnimation(.easeOut(duration: gradientDuration)) {
            gradientOpacity = 0
        }

        // Remove gradient view and call completion
        DispatchQueue.main.asyncAfter(deadline: .now() + gradientDuration) {
            showGradient = false
            onComplete?()
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        GradientRevealText(
            text: "This is a sample summary that appears with a gradient overlay that fades away.",
            font: .footnote,
            foregroundStyle: .secondary
        )
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    .padding()
}
