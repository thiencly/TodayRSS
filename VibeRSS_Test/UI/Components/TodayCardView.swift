//
//  TodayCardView.swift
//  VibeRSS_Test
//
//  Created by Thien Ly on 10/27/25.
//


//
//  TodayCardView.swift
//  TodayRSS
//
//  Purpose:
//  - Renders the compact card used in the Today screen to show the latest
//    article per source, with the source icon, title, and a one-line summary.
//
//  Used by:
//  - TodayView (inside the ScrollView/LazyVStack list of cards)
//

import SwiftUI

struct TodayCardView: View {
    let card: TodayView.TodayCard

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        .blendMode(.overlay)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    FeedIconView(iconURL: card.source.iconURL)
                        .frame(width: 26, height: 26)
                    Text(card.source.title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                Text(card.oneLine.isEmpty ? "Tap to open latest article" : card.oneLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
    }
}