//
//  RainbowGlowText.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/27/25.
//


// RainbowGlowViews.swift
// Reusable glowing text and symbol views that use SiriGradient helpers.

import SwiftUI

struct RainbowGlowText: View {
    let text: String
    var font: Font = .subheadline
    var subtle: Bool = false
    @State private var animate = false
    
    private var gradient: LinearGradient { SiriGradient.linear() }
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.clear)
            .overlay {
                gradient
                    .hueRotation(.degrees(animate ? 360 : 0))
                    .saturation(subtle ? 0.6 : 1.0)
                    .opacity(subtle ? 0.85 : 1.0)
                    .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: animate)
                    .mask(Text(text).font(font))
            }
            .shadow(color: .pink.opacity(subtle ? 0.18 : 0.35), radius: subtle ? 5 : 8, x: 0, y: 0)
            .shadow(color: .blue.opacity(subtle ? 0.15 : 0.25), radius: subtle ? 8 : 12, x: 0, y: 0)
            .shadow(color: .yellow.opacity(subtle ? 0.12 : 0.20), radius: subtle ? 12 : 16, x: 0, y: 0)
            .onAppear { animate = true }
    }
    
}

struct RainbowGlowSymbol: View {
    let systemName: String
    var font: Font = .caption2
    var subtle: Bool = false
    @State private var animate = false
    
    private var gradient: LinearGradient { SiriGradient.linear() }
    
    var body: some View {
        Image(systemName: systemName)
            .font(font)
            .foregroundStyle(.clear)
            .overlay {
                gradient
                    .hueRotation(.degrees(animate ? 360 : 0))
                    .saturation(subtle ? 0.6 : 1.0)
                    .opacity(subtle ? 0.85 : 1.0)
                    .animation(unifiedAnimation, value: animate)
                    .mask(Image(systemName: systemName).font(font))
            }
            .shadow(color: .pink.opacity(subtle ? 0.18 : 0.35), radius: subtle ? 4 : 6, x: 0, y: 0)
            .shadow(color: .blue.opacity(subtle ? 0.15 : 0.25), radius: subtle ? 6 : 10, x: 0, y: 0)
            .shadow(color: .yellow.opacity(subtle ? 0.12 : 0.20), radius: subtle ? 8 : 12, x: 0, y: 0)
            .onAppear { animate = true }
    }
}
