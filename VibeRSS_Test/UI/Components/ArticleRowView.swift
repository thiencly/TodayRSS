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
            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(state.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTapArticle)

                // Summary section
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        SummarizeButton(
                            state: buttonState
                        ) {
                            onTapSummarize()
                        }
                        .disabled(state.isError)

                        if state.isNew {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                                .accessibilityLabel("New article")
                        }
                    }

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
                }
                .padding(.top, 4)

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

    private var buttonState: SummarizeButton.ButtonState {
        if state.isGenerating {
            return .generating
        } else if state.hasSummary {
            return .hasSummary(isExpanded: state.isExpanded)
        } else {
            return .none
        }
    }
}
