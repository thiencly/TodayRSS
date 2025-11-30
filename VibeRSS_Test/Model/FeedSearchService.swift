import Foundation

struct FeedSearchResult: Identifiable, Hashable {
    let id: String
    let title: String
    let feedURL: URL
    let websiteURL: URL?
    let description: String?
    let iconURL: URL?
    let subscribers: Int?
}

actor FeedSearchService {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    func search(query: String) async throws -> [FeedSearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://cloud.feedly.com/v3/search/feeds?query=\(encoded)&count=20"

        guard let url = URL(string: urlString) else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return []
        }

        let decoded = try JSONDecoder().decode(FeedlySearchResponse.self, from: data)
        return decoded.results.compactMap { result -> FeedSearchResult? in
            guard var feedURLString = result.feedId else {
                return nil
            }

            // Remove "feed/" prefix only (not all occurrences)
            let feedPrefix = "feed/"
            if feedURLString.hasPrefix(feedPrefix) {
                feedURLString = String(feedURLString.dropFirst(feedPrefix.count))
            }

            // Upgrade HTTP to HTTPS (most sites redirect anyway)
            if feedURLString.hasPrefix("http://") {
                var components = URLComponents(string: feedURLString)
                components?.scheme = "https"
                if let httpsString = components?.string {
                    feedURLString = httpsString
                }
            }

            guard let feedURL = URL(string: feedURLString) else {
                return nil
            }

            return FeedSearchResult(
                id: result.feedId ?? UUID().uuidString,
                title: result.title ?? "Unknown",
                feedURL: feedURL,
                websiteURL: result.website.flatMap { URL(string: $0) },
                description: result.description,
                iconURL: result.iconUrl.flatMap { URL(string: $0) } ?? result.visualUrl.flatMap { URL(string: $0) },
                subscribers: result.subscribers
            )
        }
    }
}

// MARK: - Feedly API Response Models

private struct FeedlySearchResponse: Codable, Sendable {
    let results: [FeedlyFeedResult]
}

private struct FeedlyFeedResult: Codable, Sendable {
    let feedId: String?
    let title: String?
    let website: String?
    let description: String?
    let iconUrl: String?
    let visualUrl: String?
    let subscribers: Int?
}
