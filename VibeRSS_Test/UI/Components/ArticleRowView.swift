//
//  ArticleRowView.swift
//  VibeRSS_Test
//
//  Extracted article row for scroll performance optimization
//

import SwiftUI

/// Pre-computed state for an article row to avoid recomputation during scroll
struct ArticleRowState: Equatable {
    let id: UUID
    let title: String
    let link: URL
    let pubDate: Date?
    let thumbnailURL: URL?
    let sourceIconURL: URL?
    let sourceTitle: String
    let isNew: Bool
    let isRead: Bool
    let hasSummary: Bool
    let summaryText: String?
    let isExpanded: Bool
    let isError: Bool
    let isGenerating: Bool
}

/// High-performance article row view
/// Uses Equatable conformance to skip unnecessary re-renders
struct ArticleRowView: View, Equatable {
    let state: ArticleRowState
    let onTapArticle: () -> Void
    let onTapSummarize: () -> Void

    static func == (lhs: ArticleRowView, rhs: ArticleRowView) -> Bool {
        lhs.state == rhs.state
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                // Title with unread indicator
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(state.title)
                        .font(.headline)
                        .foregroundStyle(state.isRead ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    if state.isNew {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                            .accessibilityLabel("New article")
                    }
                }
                .layoutPriority(2)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTapArticle)

                // Summarize button - using liquid glass version
                // To revert to old style, change SummarizeButtonLiquidGlass to SummarizeButton
                SummarizeButtonLiquidGlass(
                    state: buttonState
                ) {
                    onTapSummarize()
                }
                .disabled(state.isError)

                // AI Summary or error
                if let summaryText = state.summaryText {
                    CollapsibleText(text: summaryText, isExpanded: state.isExpanded)
                } else if state.isError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        Text("Summarization unavailable on this device.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                // Source badge
                HStack(alignment: .center, spacing: 6) {
                    SourceBadge(iconURL: state.sourceIconURL, name: state.sourceTitle)
                    if let date = state.pubDate {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(date, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Spacer(minLength: 12)

            // Thumbnail
            if let thumb = state.thumbnailURL {
                ArticleThumbnailView(url: thumb)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTapArticle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Change to SummarizeButton.ButtonState to revert to old style
    private var buttonState: SummarizeButtonLiquidGlass.ButtonState {
        if state.isGenerating {
            return .generating
        } else if state.hasSummary {
            return .hasSummary(isExpanded: state.isExpanded)
        } else {
            return .none
        }
    }
}
