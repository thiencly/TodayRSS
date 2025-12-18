import SwiftUI

struct SavedArticlesView: View {
    @State private var savedManager = SavedArticlesManager.shared
    @State private var webLink: WebLink?
    @State private var readURLs: Set<URL> = []

    var body: some View {
        Group {
            if savedManager.savedArticles.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(savedManager.savedArticles) { article in
                        SavedArticleRow(
                            article: article,
                            isRead: readURLs.contains(article.url),
                            onTap: {
                                readURLs.insert(article.url)
                                Task { await ArticleReadStateManager.shared.markAsRead(article.url) }
                                webLink = WebLink(url: article.url, title: article.title, date: article.pubDate, thumbnailURL: article.thumbnailURL, sourceIconURL: article.sourceIconURL, sourceTitle: article.sourceTitle)
                            },
                            onUnsave: {
                                withAnimation {
                                    savedManager.unsave(url: article.url)
                                }
                            }
                        )
                    }
                    .onDelete(perform: deleteArticles)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $webLink) { w in
            ArticleReaderView(url: w.url, articleTitle: w.title, articleDate: w.date, thumbnailURL: w.thumbnailURL, sourceIconURL: w.sourceIconURL, sourceTitle: w.sourceTitle)
        }
        .onAppear {
            Task {
                let urls = savedManager.savedArticles.map { $0.url }
                let states = await ArticleReadStateManager.shared.getStates(for: urls)
                for state in states {
                    if state.isRead { readURLs.insert(state.url) }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Saved Articles")
                .font(.roundedHeadline)

            Text("Tap the heart icon in the reader or news reel to save articles for later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func deleteArticles(at offsets: IndexSet) {
        for index in offsets {
            let article = savedManager.savedArticles[index]
            savedManager.unsave(url: article.url)
        }
    }
}

// MARK: - Saved Article Row

struct SavedArticleRow: View {
    let article: SavedArticle
    let isRead: Bool
    let onTap: () -> Void
    let onUnsave: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Thumbnail
                if let thumbnailURL = article.thumbnailURL {
                    CachedAsyncImage(url: thumbnailURL, contentMode: .fill, size: CGSize(width: 80, height: 80)) {
                        thumbnailPlaceholder
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    thumbnailPlaceholder
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    Text(article.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(isRead ? .secondary : .primary)
                        .lineLimit(2)

                    // Source and date
                    HStack(spacing: 6) {
                        if let iconURL = article.sourceIconURL {
                            CachedAsyncImage(url: iconURL, size: CGSize(width: 14, height: 14)) {
                                Image(systemName: "globe")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        }

                        if let source = article.sourceTitle {
                            Text(source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let date = article.pubDate {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(date, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Saved date
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text("Saved \(article.savedDate, style: .relative)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onUnsave) {
                Label("Unsave", systemImage: "heart.slash")
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onUnsave) {
                Label("Remove from Saved", systemImage: "heart.slash")
            }
        }
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            .overlay {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
            }
    }
}
