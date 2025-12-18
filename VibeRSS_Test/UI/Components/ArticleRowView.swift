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
    let isSaved: Bool

    init(id: UUID, title: String, link: URL, pubDate: Date?, thumbnailURL: URL?, sourceIconURL: URL?, sourceTitle: String, isNew: Bool, isRead: Bool, hasSummary: Bool, summaryText: String?, isExpanded: Bool, isError: Bool, isGenerating: Bool, isSaved: Bool = false) {
        self.id = id
        self.title = title
        self.link = link
        self.pubDate = pubDate
        self.thumbnailURL = thumbnailURL
        self.sourceIconURL = sourceIconURL
        self.sourceTitle = sourceTitle
        self.isNew = isNew
        self.isRead = isRead
        self.hasSummary = hasSummary
        self.summaryText = summaryText
        self.isExpanded = isExpanded
        self.isError = isError
        self.isGenerating = isGenerating
        self.isSaved = isSaved
    }
}

/// High-performance article row view
/// Uses Equatable conformance to skip unnecessary re-renders
struct ArticleRowView: View, Equatable {
    let state: ArticleRowState
    let onTapArticle: () -> Void
    let onTapSummarize: () -> Void
    var onSave: (() -> Void)?

    static func == (lhs: ArticleRowView, rhs: ArticleRowView) -> Bool {
        lhs.state == rhs.state
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                // Title with unread indicator (inline at end of text)
                titleWithNewIndicator
                    .font(.roundedHeadline)
                    .foregroundStyle(state.isRead ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTapArticle)
                    .contextMenu {
                        if let onSave = onSave {
                            Button {
                                onSave()
                            } label: {
                                Label(
                                    state.isSaved ? "Remove from Saved" : "Save for Later",
                                    systemImage: state.isSaved ? "heart.slash" : "heart"
                                )
                            }
                        }

                        ShareLink(item: state.link) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            UIApplication.shared.open(state.link)
                        } label: {
                            Label("Open in Safari", systemImage: "safari")
                        }
                    }

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

    // Title with inline blue dot at the very end (after last character on last line)
    private var titleWithNewIndicator: Text {
        if state.isNew {
            // Use non-breaking space (\u{00A0}) so dot doesn't wrap to new line alone
            return Text(state.title) + Text("\u{00A0}") + Text(Image(systemName: "circle.fill"))
                .font(.system(size: 6))
                .foregroundColor(.blue)
                .baselineOffset(4) // Vertically center with headline text
        } else {
            return Text(state.title)
        }
    }
}
