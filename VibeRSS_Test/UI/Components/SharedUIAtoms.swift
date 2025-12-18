//
//  SharedUIAtoms.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/27/25.
//


// SharedUIAtoms.swift
// Small reusable UI components: source badge, feed icon, summary badge, and placeholder views.

import SwiftUI

struct SourceBadge: View {
    var iconURL: URL?
    var name: String
    private let iconSize: CGFloat = 20
    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let iconURL {
                    CachedAsyncImage(url: iconURL, size: CGSize(width: iconSize, height: iconSize)) {
                        Color.clear
                    }
                } else {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .frame(width: iconSize, height: iconSize)
                }
            }
            .frame(width: iconSize, height: iconSize)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(name)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

struct FeedIconView: View {
    var iconURL: URL?
    private let iconSize: CGFloat = 24
    var body: some View {
        Group {
            if let iconURL {
                CachedAsyncImage(url: iconURL, size: CGSize(width: iconSize, height: iconSize)) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .frame(width: iconSize, height: iconSize)
                }
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .frame(width: iconSize, height: iconSize)
            }
        }
        .frame(width: iconSize, height: iconSize)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct SummaryBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            RainbowGlowSymbol(systemName: "sparkles", font: Font.caption2, subtle: true)

            Text("Summary")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
        .background(
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
        )
        .overlay(
            Capsule().strokeBorder(Color.secondary.opacity(0.15))
        )
        .unifiedGlow(intensity: 0.6)
    }
}

struct ContentPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 48))
            Text("Add a source to start vibing").font(.roundedHeadline).foregroundStyle(.secondary)
        }.padding()
    }
}
