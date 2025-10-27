// ButtonsAndStyles.swift
// Reusable button style (glass pill) and a floating refresh button used across screens.

import SwiftUI

struct FloatingRefreshButton: View {
    var isLoading: Bool
    var action: () -> Void

    var body: some View {
        Button(action: { action() }) {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Circle())
        .overlay(
            Circle().strokeBorder(Color.secondary.opacity(0.2))
        )
        .shadow(radius: 2, x: 0, y: 1)
        .disabled(isLoading)
        .accessibilityLabel("Refresh")
    }
}

struct GlassPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .transaction { $0.animation = nil }
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.98 : 1.0)
            .overlay(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(configuration.isPressed ? 0.22 : 0.00),
                                Color.white.opacity(configuration.isPressed ? 0.10 : 0.00)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.plusLighter)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(configuration.isPressed ? 0.35 : 0.0),
                                Color.white.opacity(configuration.isPressed ? 0.06 : 0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: configuration.isPressed ? 1.0 : 0.0
                    )
                    .blur(radius: configuration.isPressed ? 0.8 : 0.0)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(configuration.isPressed ? 0.20 : 0.0), lineWidth: 1)
                    .blendMode(.overlay)
            )
            .shadow(color: Color.white.opacity(configuration.isPressed ? 0.20 : 0.0), radius: configuration.isPressed ? 6 : 0, x: 0, y: 0)
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.08 : 0.0), radius: configuration.isPressed ? 5 : 0, x: 0, y: 2)
    }
}
