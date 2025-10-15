// VibeRSS.swift
// SwiftUI RSS reader starter with feed icons + auto-favicon fetch
// iOS 17+ • SwiftUI • async/await • XMLParser (RSS + Atom)

import SwiftUI
import Combine
import Foundation
import SafariServices
import UIKit
import CryptoKit
import UniformTypeIdentifiers
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Shared Siri-like Gradient & Glow
struct SiriGradient {
    static let colors: [Color] = [
        Color.cyan, Color.blue, Color.indigo, Color.purple, Color.pink, Color.cyan
    ]

    static func linear(start: UnitPoint = .leading, end: UnitPoint = .trailing) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: start, endPoint: end)
    }

    static func angular(center: UnitPoint = .center, angle: Angle = .degrees(0)) -> AngularGradient {
        AngularGradient(colors: colors, center: .center, angle: angle)
    }
}

struct UnifiedGlowStyle: ViewModifier {
    var intensity: Double = 1.0
    func body(content: Content) -> some View {
        content
            .shadow(color: .blue.opacity(0.25 * intensity), radius: 6)
            .shadow(color: .purple.opacity(0.20 * intensity), radius: 10)
            .shadow(color: .pink.opacity(0.15 * intensity), radius: 14)
    }
}

extension View {
    func unifiedGlow(intensity: Double = 1.0) -> some View { self.modifier(UnifiedGlowStyle(intensity: intensity)) }
}

let unifiedAnimation: Animation = .linear(duration: 0.9).repeatForever(autoreverses: false)

// MARK: - Models
struct Feed: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var url: URL
    var iconURL: URL? // optional feed icon
    var folderID: UUID? // optional folder assignment

    init(id: UUID = UUID(), title: String, url: URL, iconURL: URL? = nil, folderID: UUID? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.iconURL = iconURL
        self.folderID = folderID
    }
}

struct FeedItem: Identifiable, Hashable, Equatable {
    let id = UUID()
    var title: String
    var link: URL
    var summary: String
    var pubDate: Date?
    var author: String?
    var thumbnailURL: URL?
    // Source attribution (set by view models after parsing)
    var sourceID: UUID? = nil
    var sourceTitle: String? = nil
    var sourceIconURL: URL? = nil

    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.link == rhs.link &&
        lhs.summary == rhs.summary &&
        lhs.pubDate == rhs.pubDate &&
        lhs.author == rhs.author &&
        lhs.thumbnailURL == rhs.thumbnailURL &&
        lhs.sourceID == rhs.sourceID &&
        lhs.sourceTitle == rhs.sourceTitle &&
        lhs.sourceIconURL == rhs.sourceIconURL
    }
}

struct Folder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

#if canImport(FoundationModels)
@Generable(description: "A concise inline summary for streaming")
struct InlineSummary {
    @Guide(description: "The concise summary text")
    var text: String
}
#endif

// MARK: - Terminology aliases
typealias Source = Feed
typealias Article = FeedItem

// MARK: - Persistence (simple)
@MainActor
final class FeedStore: ObservableObject {
    @Published var feeds: [Feed] = [] {
        didSet { debounceSaveFeeds() }
    }
    @Published var folders: [Folder] = [] {
        didSet { debounceSaveFolders() }
    }

    private let faviconService = FaviconService()
    private let key = "viberss.feeds"
    private let folderKey = "viberss.folders"

    private var saveDebounceTask: Task<Void, Never>? = nil
    private var saveFoldersDebounceTask: Task<Void, Never>? = nil

    init() {
        load()
        loadFolders()
        if feeds.isEmpty {
            var initialFeeds: [Feed] = []

            if let url1 = URL(string: "https://www.theverge.com/rss/index.xml") {
                let icon1 = URL(string: "https://www.theverge.com/apple-touch-icon.png")
                initialFeeds.append(Feed(title: "The Verge", url: url1, iconURL: icon1))
            }
            if let url2 = URL(string: "https://www.macrumors.com/macrumors.xml") {
                let icon2 = URL(string: "https://cdn.macrumors.com/images-new/macrumors-og.png")
                initialFeeds.append(Feed(title: "MacRumors", url: url2, iconURL: icon2))
            }
            feeds = initialFeeds
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(feeds)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("Save error: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        do {
            feeds = try JSONDecoder().decode([Feed].self, from: data)
        } catch {
            print("Load error: \(error)")
        }
    }

    private func saveFolders() {
        do {
            let data = try JSONEncoder().encode(folders)
            UserDefaults.standard.set(data, forKey: folderKey)
        } catch {
            print("Save folders error: \(error)")
        }
    }

    private func loadFolders() {
        guard let data = UserDefaults.standard.data(forKey: folderKey) else { return }
        do {
            folders = try JSONDecoder().decode([Folder].self, from: data)
        } catch {
            print("Load folders error: \(error)")
        }
    }

    private func debounceSaveFeeds() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run { self.save() }
        }
    }

    private func debounceSaveFolders() {
        saveFoldersDebounceTask?.cancel()
        saveFoldersDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run { self.saveFolders() }
        }
    }

    func assign(_ feed: Feed, to folder: Folder?) {
        guard let idx = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        feeds[idx].folderID = folder?.id
    }

    func removeFolder(_ folder: Folder) {
        // Unassign any feeds in this folder
        for i in feeds.indices {
            if feeds[i].folderID == folder.id {
                feeds[i].folderID = nil
            }
        }
        // Remove the folder
        folders.removeAll { $0.id == folder.id }
    }

    func sources(in folder: Folder?) -> [Feed] {
        guard let folder else { return feeds }
        return feeds.filter { $0.folderID == folder.id }
    }

    func backfillIcons() {
        Task { [feeds] in
            for i in feeds.indices {
                if self.feeds[i].iconURL == nil {
                    if let icon = await faviconService.resolveIcon(for: self.feeds[i].url) {
                        self.feeds[i].iconURL = icon
                    }
                }
            }
        }
    }

    func refreshIcon(for feed: Feed) async {
        guard let idx = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        if let icon = await faviconService.resolveIcon(for: feed.url) {
            feeds[idx].iconURL = icon
        }
    }
}

// MARK: - Errors
enum FeedError: Error, LocalizedError { case badURL, requestFailed, parseFailed
    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid feed URL"
        case .requestFailed: return "Network request failed"
        case .parseFailed: return "Couldn't parse feed"
        }
    }
}

// MARK: - Networking & Parsing
actor FeedService {
    func loadItems(from url: URL) async throws -> [FeedItem] {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        try Task.checkCancellation()
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedError.requestFailed
        }
        if let xml = String(data: data, encoding: .utf8), xml.contains("<feed") { // Atom heuristic
            return try await parseAtom(data)
        } else {
            return try await parseRSS(data)
        }
    }

    @MainActor private func parseRSS(_ data: Data) throws -> [FeedItem] {
        let parser = RSSParser()
        return try parser.parse(data: data)
    }

    @MainActor private func parseAtom(_ data: Data) throws -> [FeedItem] {
        let parser = AtomParser()
        return try parser.parse(data: data)
    }
}

// MARK: - XML Parsers
final class RSSParser: NSObject, XMLParserDelegate {
    private var items: [FeedItem] = []
    private var currentTitle = ""
    private var currentLink: URL?
    private var currentDescription = ""
    private var currentPubDate: Date?
    private var currentAuthor: String?
    private var currentThumbnail: URL?
    private var currentElement = ""

    func parse(data: Data) throws -> [FeedItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { throw FeedError.parseFailed }
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        if currentElement == "item" { resetItem() }
        if currentElement == "link", let href = attributeDict["href"], let url = URL(string: href) {
            currentLink = url // some feeds put link in <link href="..."/>
        }
        if currentElement == "enclosure" {
            if let type = attributeDict["type"], type.lowercased().hasPrefix("image"),
               let href = attributeDict["url"], let u = URL(string: href) {
                currentThumbnail = currentThumbnail ?? u
            }
        }
        if currentElement == "media:thumbnail" {
            if let href = attributeDict["url"], let u = URL(string: href) {
                currentThumbnail = currentThumbnail ?? u
            }
        }
        if currentElement == "media:content" {
            if let type = attributeDict["type"], type.lowercased().hasPrefix("image"),
               let href = attributeDict["url"], let u = URL(string: href) {
                currentThumbnail = currentThumbnail ?? u
            } else if let medium = attributeDict["medium"], medium.lowercased() == "image",
                      let href = attributeDict["url"], let u = URL(string: href) {
                currentThumbnail = currentThumbnail ?? u
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch currentElement {
        case "title": currentTitle += string
        case "link": if currentLink == nil { currentLink = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) }
        case "description", "summary", "content:encoded": currentDescription += string
        case "pubdate": currentPubDate = DateFormatter.rfc822.date(from: string.trimmingCharacters(in: .whitespacesAndNewlines))
        case "author", "dc:creator": currentAuthor = (currentAuthor ?? "") + string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.lowercased() == "item" {
            if let link = currentLink {
                var thumb = currentThumbnail
                if thumb == nil {
                    thumb = extractFirstImageURL(from: currentDescription, relativeTo: link)
                }
                let title = currentTitle.trimmed()
                let desc = currentDescription.trimmedHTML()
                let author = currentAuthor?.trimmed()
                items.append(FeedItem(title: title, link: link, summary: desc, pubDate: currentPubDate, author: author, thumbnailURL: thumb))
            }
            resetItem()
        }
        currentElement = ""
    }

    private func resetItem() {
        currentTitle = ""; currentLink = nil; currentDescription = ""; currentPubDate = nil; currentAuthor = nil; currentThumbnail = nil
    }
}

final class AtomParser: NSObject, XMLParserDelegate {
    private var items: [FeedItem] = []
    private var currentTitle = ""
    private var currentLink: URL?
    private var currentSummary = ""
    private var currentUpdated: Date?
    private var currentAuthor: String?
    private var currentThumbnail: URL?
    private var currentElement = ""

    func parse(data: Data) throws -> [FeedItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { throw FeedError.parseFailed }
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        if currentElement == "entry" { resetItem() }
        if currentElement == "link" {
            if let rel = attributeDict["rel"], rel.lowercased() == "enclosure",
               let type = attributeDict["type"], type.lowercased().hasPrefix("image"),
               let href = attributeDict["href"], let u = URL(string: href) {
                currentThumbnail = currentThumbnail ?? u
            } else if let href = attributeDict["href"], let url = URL(string: href) {
                currentLink = currentLink ?? url
            }
        }
        if currentElement == "media:thumbnail" {
            if let href = attributeDict["url"], let u = URL(string: href) {
                currentThumbnail = currentThumbnail ?? u
            }
        }
        if currentElement == "media:content" {
            if let type = attributeDict["type"], type.lowercased().hasPrefix("image"),
               let href = attributeDict["url"], let u = URL(string: href) {
                currentThumbnail = currentThumbnail ?? u
            } else if let medium = attributeDict["medium"], medium.lowercased() == "image",
                      let href = attributeDict["url"], let u = URL(string: href) {
                currentThumbnail = currentThumbnail ?? u
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch currentElement {
        case "title": currentTitle += string
        case "summary", "content": currentSummary += string
        case "updated", "published": currentUpdated = ISO8601DateFormatter().date(from: string.trimmingCharacters(in: .whitespacesAndNewlines))
        case "name": currentAuthor = (currentAuthor ?? "") + string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.lowercased() == "entry" {
            if let link = currentLink {
                var thumb = currentThumbnail
                if thumb == nil {
                    thumb = extractFirstImageURL(from: currentSummary, relativeTo: link)
                }
                let title = currentTitle.trimmed()
                let summary = currentSummary.trimmedHTML()
                let author = currentAuthor?.trimmed()
                items.append(FeedItem(title: title, link: link, summary: summary, pubDate: currentUpdated, author: author, thumbnailURL: thumb))
            }
            resetItem()
        }
        currentElement = ""
    }

    private func resetItem() {
        currentTitle = ""; currentLink = nil; currentSummary = ""; currentUpdated = nil; currentAuthor = nil; currentThumbnail = nil
    }
}

// MARK: - Date formats & helpers
extension DateFormatter {
    static let rfc822: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return df
    }()
}

extension String {
    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
    func trimmedHTML() -> String {
        let s = self.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed()
    }
}

func extractFirstImageURL(from html: String, relativeTo base: URL?) -> URL? {
    let pattern = "<img[^>]*src=[\"']([^\"']+)[\"']"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let ns = html as NSString
    let range = NSRange(location: 0, length: ns.length)
    if let m = regex.firstMatch(in: html, options: [], range: range) {
        let r = m.range(at: 1)
        let src = ns.substring(with: r)
        if let base { return URL(string: src, relativeTo: base)?.absoluteURL }
        return URL(string: src)
    }
    return nil
}

// MARK: - ViewModels
@MainActor
final class ItemsViewModel: ObservableObject {
    @Published var items: [Article] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = FeedService()

    func load(for source: Source) async {
        isLoading = true; errorMessage = nil
        do {
            var result = try await service.loadItems(from: source.url)
            for i in result.indices {
                result[i].sourceID = source.id
                result[i].sourceTitle = source.title
                result[i].sourceIconURL = source.iconURL
            }
            guard let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()) else {
                // If date math fails, keep existing items order without filtering
                items = result.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
                isLoading = false
                return
            }
            // Updated filter logic for pubDate nil items kept
            result = result.filter { item in
                if let d = item.pubDate { return d >= cutoff } else { return true }
            }
            items = result.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Folder aggregated items VM
@MainActor
final class FolderItemsViewModel: ObservableObject {
    @Published var items: [Article] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = FeedService()

    func load(for folder: Folder, feeds: [Feed]) async {
        isLoading = true; errorMessage = nil
        let sources = feeds.filter { $0.folderID == folder.id }
        var all: [Article] = []
        await withTaskGroup(of: [FeedItem].self) { group in
            for src in sources {
                group.addTask {
                    do {
                        var r = try await self.service.loadItems(from: src.url)
                        for i in r.indices {
                            r[i].sourceID = src.id
                            r[i].sourceTitle = src.title
                            r[i].sourceIconURL = src.iconURL
                        }
                        return r
                    } catch { return [] }
                }
            }
            for await result in group {
                all.append(contentsOf: result)
            }
        }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()) else {
            // If date math fails, sort without filtering
            items = all.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            isLoading = false
            return
        }
        // Updated filter logic for pubDate nil items kept
        let filtered = all.filter { if let d = $0.pubDate { return d >= cutoff } else { return true } }
        items = filtered.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        isLoading = false
    }

    func loadAll(feeds: [Feed]) async {
        isLoading = true; errorMessage = nil
        let sources = feeds
        var all: [Article] = []
        await withTaskGroup(of: [FeedItem].self) { group in
            for src in sources {
                group.addTask {
                    do {
                        var r = try await self.service.loadItems(from: src.url)
                        for i in r.indices {
                            r[i].sourceID = src.id
                            r[i].sourceTitle = src.title
                            r[i].sourceIconURL = src.iconURL
                        }
                        return r
                    } catch { return [] }
                }
            }
            for await result in group {
                all.append(contentsOf: result)
            }
        }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()) else {
            // If date math fails, sort without filtering
            items = all.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            isLoading = false
            return
        }
        // Updated filter logic for pubDate nil items kept
        let filtered = all.filter { if let d = $0.pubDate { return d >= cutoff } else { return true } }
        items = filtered.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        isLoading = false
    }
}

// MARK: - Favicon service (auto fetch)
actor FaviconService {
    func resolveIcon(for feedURL: URL) async -> URL? {
        // Derive site base from feed URL
        guard var comps = URLComponents(url: feedURL, resolvingAgainstBaseURL: false) else { return nil }
        comps.path = "/"; comps.query = nil; comps.fragment = nil
        guard let base = comps.url else { return nil }

        // 1) Parse HTML for <link rel="icon" ...> / apple-touch-icon and choose the largest
        if let html = await fetchHTML(from: base) {
            let hrefs = iconLinkCandidates(in: html)
            for href in hrefs {
                if let icon = URL(string: href, relativeTo: base), await urlExists(icon) {
                    return icon.absoluteURL
                }
            }
        }

        // 2) Try a set of common icon paths (best-first)
        for candidate in commonIconURLs(for: base) {
            if await urlExists(candidate) {
                return candidate.absoluteURL
            }
        }

        return nil
    }

    private func absolute(_ url: URL) -> URL { url }

    private func urlExists(_ url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 3
        do {
            try Task.checkCancellation()
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse { return (200..<400).contains(http.statusCode) }
        } catch {}
        // Some servers reject HEAD—fallback to GET small
        do {
            try Task.checkCancellation()
            var getReq = URLRequest(url: url)
            getReq.timeoutInterval = 3
            let (_, resp) = try await URLSession.shared.data(for: getReq)
            if let http = resp as? HTTPURLResponse { return (200..<400).contains(http.statusCode) }
        } catch {}
        return false
    }

    private func fetchHTML(from url: URL) async -> String? {
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            try Task.checkCancellation()
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return String(data: data, encoding: .utf8)
        } catch { return nil }
    }

    private func commonIconURLs(for base: URL) -> [URL] {
        let paths = [
            "/apple-touch-icon.png",
            "/apple-touch-icon-precomposed.png",
            "/favicon-196x196.png",
            "/android-chrome-192x192.png",
            "/favicon-180x180.png",
            "/favicon-152x152.png",
            "/favicon-120x120.png",
            "/favicon-96x96.png",
            "/favicon-64x64.png",
            "/favicon-32x32.png",
            "/favicon.png",
            "/favicon.ico"
        ]
        return paths.compactMap { URL(string: $0, relativeTo: base) }
    }

    private func iconLinkCandidates(in html: String) -> [String] {
        // Find all <link ...> tags that declare an icon rel, then extract href and sizes
        let linkPattern = "<link[^>]*?rel=[\"'][^\"']*(?:icon|apple-touch-icon)[^\"']*[\"'][^>]*>"
        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = linkRegex.matches(in: html, options: [], range: range)

        struct Candidate { let href: String; let size: Int }
        var candidates: [Candidate] = []

        for m in matches {
            let tag = ns.substring(with: m.range) as NSString
            // href
            var href: String?
            if let hrefRegex = try? NSRegularExpression(pattern: "href=[\"']([^\"']+)[\"']", options: [.caseInsensitive]),
               let hm = hrefRegex.firstMatch(in: tag as String, options: [], range: NSRange(location: 0, length: tag.length)) {
                let hrefRange = hm.range(at: 1)
                href = tag.substring(with: hrefRange)
            }
            guard let hrefStr = href else { continue }
            // sizes
            var sizeValue = 0
            if let sizesRegex = try? NSRegularExpression(pattern: "sizes=[\"'](\\d+)x(\\d+)[\"']", options: [.caseInsensitive]),
               let sm = sizesRegex.firstMatch(in: tag as String, options: [], range: NSRange(location: 0, length: tag.length)) {
                let w = Int(tag.substring(with: sm.range(at: 1))) ?? 0
                let h = Int(tag.substring(with: sm.range(at: 2))) ?? 0
                sizeValue = max(w, h)
            } else {
                // If no size, prefer apple-touch over generic icon by giving a moderate default
                if (tag as String).range(of: "apple-touch-icon", options: .caseInsensitive) != nil {
                    sizeValue = 180
                } else {
                    sizeValue = 32
                }
            }
            candidates.append(Candidate(href: hrefStr, size: sizeValue))
        }

        // Sort by size descending and return hrefs
        return candidates.sorted { $0.size > $1.size }.map { $0.href }
    }
}

// MARK: - Image Disk Cache + Cached Image View
actor ImageDiskCache {
    static let shared = ImageDiskCache()
    private let fm = FileManager.default
    private let directory: URL
    private let memCache = NSCache<NSString, UIImage>()

    init() {
        // Use a local FileManager to avoid capturing the actor-isolated property in nonisolated autoclosures.
        let localFM = FileManager.default
        let caches = localFM.urls(for: .cachesDirectory, in: .userDomainMask)
        let base: URL
        if let first = caches.first {
            base = first
        } else {
            base = localFM.temporaryDirectory
        }
        directory = base.appendingPathComponent("ImageCache", conformingTo: .directory)
        try? localFM.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for url: URL) async -> UIImage? {
        let file = fileURL(for: url)
        let key = file.lastPathComponent as NSString

        if let cachedMem = memCache.object(forKey: key) {
            return cachedMem
        }

        if fm.fileExists(atPath: file.path), let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            memCache.setObject(image, forKey: key)
            return image
        }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            try Task.checkCancellation()
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                try? data.write(to: file, options: [.atomic])
                if let image = UIImage(data: data) {
                    memCache.setObject(image, forKey: key)
                    return image
                }
            }
        } catch {}
        return nil
    }

    private func fileURL(for url: URL) -> URL {
        let name = sha256(url.absoluteString)
        return directory.appendingPathComponent(name).appendingPathExtension("img")
    }

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fit
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: UIImage?
    @State private var taskID = UUID()

    var body: some View {
        Group {
            if let image {
                if contentMode == .fill {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            } else {
                placeholder()
            }
        }
        .task(id: url?.absoluteString ?? "") { await load() }
    }

    private func load() async {
        guard let url else { return }
        if let img = await ImageDiskCache.shared.image(for: url) {
            await MainActor.run { image = img }
        }
    }
}

struct ArticleThumbnailView: View {
    let url: URL
    var body: some View {
        CachedAsyncImage(url: url, contentMode: .fill) {
            Rectangle().fill(.quaternary)
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// REPLACED RainbowGlowText with subtle option
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
            .scaleEffect(glows ? (pulse ? 1.12 : 1.0) : 1.0)
    }

    @State private var glows: Bool = false
    @State private var pulse: Bool = false
}

// We will fix scaleEffect in SummarizeButton below instead, removing here

struct SourceBadge: View {
    var iconURL: URL?
    var name: String
    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let iconURL {
                    CachedAsyncImage(url: iconURL) {
                        Color.clear
                    }
                } else {
                    Image(systemName: "dot.radiowaves.left.and.right").resizable().scaledToFit().foregroundStyle(.secondary)
                }
            }
            .frame(width: 17, height: 17)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(name)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

struct FeedIconView: View {
    var iconURL: URL?
    var body: some View {
        Group {
            if let iconURL {
                CachedAsyncImage(url: iconURL) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// Unified SummaryControl (replaces separate pill + badge)
struct SummaryBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            RainbowGlowSymbol(systemName: "sparkles", font: .caption2, subtle: true)
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

// REPLACE SpinningSmokeyGlow with TimelineView-driven rotation and stronger smoke
private struct SpinningSmokeyGlow: View {
    var pulse: Bool

    // A rotating angular gradient ring that sits on the button border
    private func ring(angle: Angle) -> some View {
        Capsule()
            .strokeBorder(
                AngularGradient(
                    colors: SiriGradient.colors,
                    center: .center,
                    angle: angle
                ),
                lineWidth: 3
            )
            .opacity(0.9)
    }

    // Soft smoky wisps that extend beyond the border
    private func smoke(angle: Angle) -> some View {
        ZStack {
            Capsule()
                .fill(AngularGradient(colors: SiriGradient.colors, center: .center, angle: angle))
                .opacity(0.42)
                .blur(radius: 30)
                .scaleEffect(pulse ? 1.14 : 1.08)

            Capsule()
                .fill(AngularGradient(colors: SiriGradient.colors, center: .center, angle: angle))
                .opacity(0.26)
                .blur(radius: 48)
                .scaleEffect(pulse ? 1.22 : 1.14)

            Capsule()
                .fill(AngularGradient(colors: SiriGradient.colors, center: .center, angle: angle))
                .opacity(0.16)
                .blur(radius: 72)
                .scaleEffect(pulse ? 1.32 : 1.22)
        }
        .padding(-26)
    }

    var body: some View {
        // Drive rotation continuously with TimelineView so it won't stall on state changes
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            // 8 seconds per full rotation for a calm motion
            let seconds = context.date.timeIntervalSinceReferenceDate
            let progress = seconds.truncatingRemainder(dividingBy: 8.0) / 8.0
            let angle = Angle(degrees: progress * 360.0)

            ZStack {
                smoke(angle: .degrees(0))
                ring(angle: .degrees(0))
            }
            .rotationEffect(angle)
            .allowsHitTesting(false)
        }
    }
}

// REPLACE SummaryControl with simpler SummarizeButton (always shows Summarize label)
struct SummarizeButton: View {
    enum ButtonState {
        case none
        case generating
        case hasSummary(isExpanded: Bool)
    }

    var state: ButtonState
    var action: () -> Void

    // Visual state
    @State private var pulse = false
    // Removed: @State private var isPressed = false

    // Updated rotatingGlowOverlay per instruction
    @ViewBuilder
    private func rotatingGlowOverlay() -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            // Faster spin when idle, slightly slower when generating to reduce distraction
            let period: Double = isGenerating ? 2.0 : 6.0 // seconds per full rotation
            // Brighter glow when idle
            let baseGlowOpacity: Double = isGenerating ? 3 : 0.5
            let blurFill: CGFloat = isGenerating ? 58 : 52
            let blur1: CGFloat = isGenerating ? 44 : 40
            let blur2: CGFloat = isGenerating ? 84 : 76
            let saturationBoost: Double = isGenerating ? 1.55 : 1.35

            let rotation = Angle(degrees: (seconds.truncatingRemainder(dividingBy: period) / period) * 360.0)

            ZStack {
                Capsule()
                    .fill(
                        AngularGradient(colors: SiriGradient.colors, center: .center, angle: .degrees(0))
                    )
                    .saturation(saturationBoost)
                    .opacity(baseGlowOpacity * 0.55)
                    .blur(radius: blurFill)
                    .blendMode(.plusLighter)

                Capsule()
                    .strokeBorder(
                        AngularGradient(colors: SiriGradient.colors, center: .center, angle: .degrees(0)),
                        lineWidth: 3
                    )
                    .saturation(saturationBoost)
                    .opacity(baseGlowOpacity)
                    .blur(radius: blur1)
                    .blendMode(.plusLighter)

                Capsule()
                    .strokeBorder(
                        AngularGradient(colors: SiriGradient.colors, center: .center, angle: .degrees(0)),
                        lineWidth: 2
                    )
                    .saturation(saturationBoost)
                    .opacity(baseGlowOpacity * 0.9)
                    .blur(radius: blur2)
                    .blendMode(.plusLighter)
            }
            .rotationEffect(rotation)
            .padding(-22)
            .allowsHitTesting(false)
        }
    }

    // Removed entire progressStreakOverlay(isGenerating:) helper and all references

    // Break out the static chrome overlays
    @ViewBuilder
    private func chromeOverlays() -> some View {
        ZStack {
            Capsule()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                .blendMode(.overlay)
            Capsule()
                .strokeBorder(Color.secondary.opacity(0.20), lineWidth: 1)
        }
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(colors: [
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.15),
                        .clear
                    ], startPoint: .top, endPoint: .bottom), lineWidth: 1
                )
                .opacity(0.75)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(colors: [
                        .clear,
                        Color.black.opacity(0.10)
                    ], startPoint: .top, endPoint: .bottom), lineWidth: 1
                )
        )
    }

    private var title: String {
        switch state {
        case .none, .generating: return "Summarize"
        case .hasSummary: return "Summary"
        }
    }

    private var showChevron: Bool {
        if case .hasSummary = state { return true }
        return false
    }

    private var isExpanded: Bool {
        if case let .hasSummary(expanded) = state { return expanded }
        return false
    }

    private var isGenerating: Bool {
        if case .generating = state { return true }
        return false
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                            .transition(.opacity)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .scaleEffect(1.0)
                    }
                }

                Text(title)
                    .font(.callout.weight(.semibold))

                Spacer(minLength: 4)

                if showChevron {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Capsule())
        }
        .buttonStyle(GlassPillStyle())
        .background(
            // Base glass material
            Capsule()
                .fill(.thinMaterial)
        )
        // Siri-like glow halo placed outside clipping so it’s visible
        .overlay(
            rotatingGlowOverlay()
        )
        // Removed .overlay(progressStreakOverlay(isGenerating: isGenerating))
        .overlay(
            chromeOverlays()
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        .scaleEffect(isGenerating ? 1.01 : 1.0)
        .animation(isGenerating ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: isGenerating)
        .onAppear {
            // Removed pulse animation on appear
        }
        // Removed onChange(of: isGenerating)
        .accessibilityLabel(title)
    }
}

private struct GlassPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Disable implicit animations so press feedback is instantaneous
            .transaction { $0.animation = nil }
            // System-like immediate press response
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.98 : 1.0)
            // Luminance lift on press (no animation)
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
            // Soft outer halo on press (no animation)
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
            // Gentle inner highlight rim
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(configuration.isPressed ? 0.20 : 0.0), lineWidth: 1)
                    .blendMode(.overlay)
            )
            // Subtle shadow tweak on press
            .shadow(color: Color.white.opacity(configuration.isPressed ? 0.20 : 0.0), radius: configuration.isPressed ? 6 : 0, x: 0, y: 0)
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.08 : 0.0), radius: configuration.isPressed ? 5 : 0, x: 0, y: 2)
    }
}

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

struct ContentPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 48))
            Text("Add a source to start vibing").font(.headline).foregroundStyle(.secondary)
        }.padding()
    }
}

// Inserted CollapsibleText view before FeedDetailView
struct CollapsibleText: View {
    let text: String
    let isExpanded: Bool
    private let collapsedLineCount: Int = 3

    var body: some View {
        Group {
            if isExpanded {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
                    .contentTransition(.opacity)
            } else {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(collapsedLineCount)
                    .layoutPriority(1)
                    .contentTransition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: isExpanded)
    }
}

// Modified struct FeedDetailView with refreshID property
struct FeedDetailView: View {
    let source: Source
    var refreshID: UUID = UUID()
    @StateObject private var vm = ItemsViewModel()
    @State private var webLink: WebLink?
    @State private var summarizingID: UUID?
    @State private var inlineSummaries: [UUID: String] = [:]
    @State private var expandedSummaries: Set<UUID> = []
    @State private var summaryErrors: Set<UUID> = []
    @State private var hasCachedText: Set<UUID> = [] // <-- Inserted here
    
    // Removed @State private var measuredSummaryHeights: [UUID: CGFloat] = [:]

    @AppStorage("summaryLength") private var summaryLengthRaw: String = "short"
    @State private var aiSummarized: Set<UUID> = []
    @State private var currentDay: Date? = nil
    @State private var suppressNextRowTap = false

    var body: some View {
        Group {
            if vm.isLoading && vm.items.isEmpty {
                ProgressView().controlSize(.large)
            } else if let error = vm.errorMessage, vm.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).multilineTextAlignment(.center)
                    Button("Retry") { Task { await vm.load(for: source) } }
                }.padding()
            } else {
                List(vm.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)

                            Group {
                                let isError = summaryErrors.contains(item.id)
                                let aiSummary = inlineSummaries[item.id]

                                // Modified SummarizeButton per instruction wrapped in HStack with indicator
                                HStack(spacing: 6) {
                                    SummarizeButton(
                                        state: { () -> SummarizeButton.ButtonState in
                                            if summarizingID == item.id {
                                                return .generating
                                            }
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "medium") ? .medium : .short
                                            let hasCached = (aiSummary != nil) || ArticleSummarizer.hasCachedSummary(url: item.link, length: length)
                                            if hasCached {
                                                return .hasSummary(isExpanded: expandedSummaries.contains(item.id))
                                            } else {
                                                return .none
                                            }
                                        }()
                                    ) {
                                        // Toggle expand/collapse if summary exists; otherwise start summarization
                                        suppressNextRowTap = true
                                        let hasSummary = (aiSummary != nil)
                                        if hasSummary {
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "medium") ? .medium : .short
                                            if expandedSummaries.contains(item.id) {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    expandedSummaries.remove(item.id)
                                                }
                                                Task { await ArticleSummarizer.shared.setExpanded(false, url: item.link, length: length) }
                                            } else {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    expandedSummaries.insert(item.id)
                                                }
                                                Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
                                            }
                                        } else if summarizingID != item.id {
                                            Task { await summarize(item) }
                                        }
                                    }
                                    .disabled(isError)

                                    // Tiny indicator when readable text is cached for this article
                                    if hasCachedText.contains(item.id) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                            .accessibilityLabel("Cached text available")
                                    }
                                }

                                // Stable summary container prevents title jump by reserving height
                                ZStack(alignment: .topLeading) {
                                    if let aiSummary {
                                        CollapsibleText(text: aiSummary, isExpanded: expandedSummaries.contains(item.id))
                                    } else if isError {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                            Text("Summarization unavailable on this device.")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                // Removed .animation(.snappy(duration: 0.25), value: expandedSummaries.contains(item.id))
                            }

                            HStack(alignment: .center, spacing: 6) {
                                SourceBadge(iconURL: item.sourceIconURL ?? source.iconURL, name: item.sourceTitle ?? source.title)
                                if let date = item.pubDate {
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
                        if let thumb = item.thumbnailURL {
                            ArticleThumbnailView(url: thumb)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DayAnchorReporter(date: item.pubDate, coordinateSpaceName: "FeedListScroll"))
                    .id(item.id)
                    .transaction { $0.disablesAnimations = false }
                }
                .listStyle(.plain)
                .transaction { $0.animation = nil }
                .refreshable { await vm.load(for: source) }
                .coordinateSpace(name: "FeedListScroll")
                .task(id: vm.items.map { $0.id }) { preloadSummaries(for: vm.items) }
                .onChange(of: summaryLengthRaw) { _, _ in }
                .onPreferenceChange(DayAnchorsKey.self) { anchors in
                    guard !anchors.isEmpty else {
                        currentDay = nil
                        return
                    }
                    let sorted = anchors.sorted { a, b in
                        let aScore = (a.minY >= 0) ? a.minY : (100000 + abs(a.minY))
                        let bScore = (b.minY >= 0) ? b.minY : (100000 + abs(b.minY))
                        return aScore < bScore
                    }
                    let topDay = sorted.first?.dayStart
                    if currentDay != topDay {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            currentDay = topDay
                        }
                    }
                }
                .safeAreaInset(edge: .top) {
                    if let d = currentDay {
                        HStack {
                            FloatingDayChip(date: d)
                            Spacer()
                        }
                        .padding(.top, 4)
                        .padding(.leading, 8)
                        .padding(.trailing, 8)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingRefreshButton(isLoading: vm.isLoading) {
                Task { await vm.load(for: source) }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 24)
        }
        .task(id: refreshID) { await vm.load(for: source) }
        .navigationTitle(source.title)
        .sheet(item: $webLink) { w in
            SafariView(url: w.url).ignoresSafeArea()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("Summary Length") {
                        Button {
                            summaryLengthRaw = "short"
                        } label: {
                            HStack {
                                Text("Short")
                                if summaryLengthRaw == "short" { Image(systemName: "checkmark") }
                            }
                        }
                        Button {
                            summaryLengthRaw = "medium"
                        } label: {
                            HStack {
                                Text("Medium")
                                if summaryLengthRaw == "medium" { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    Button("Clear Summaries", role: .destructive) {
                        inlineSummaries.removeAll()
                        aiSummarized.removeAll()
                        expandedSummaries.removeAll()
                        summaryErrors.removeAll()
                        Task { await ArticleSummarizer.shared.clearCache() }
                    }
                    Button("Clear Article Text Cache", role: .destructive) {
                        Task { await ArticleTextCache.shared.clear() }
                    }
                } label: {
                    Image(systemName: "sparkles")
                }
            }
        }
    }

    private func preloadSummaries(for items: [Article]) {
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "medium") ? .medium : .short
        Task { @MainActor in
            var updated = inlineSummaries
            var expanded = expandedSummaries
            var cachedFlags = hasCachedText // <-- Added

            for item in items {
                if updated[item.id] == nil, let cached = await ArticleSummarizer.shared.cachedSummary(for: item.link, length: length) {
                    updated[item.id] = cached
                }
                // Restore expansion state from persisted store (default collapsed)
                if await ArticleSummarizer.shared.isExpanded(url: item.link, length: length) {
                    expanded.insert(item.id)
                } else {
                    expanded.remove(item.id)
                }
                // Update cached text indicator
                if await ArticleTextCache.shared.cachedText(for: item.link) != nil {
                    cachedFlags.insert(item.id)
                } else {
                    cachedFlags.remove(item.id)
                }
            }
            inlineSummaries = updated
            expandedSummaries = expanded
            hasCachedText = cachedFlags // <-- Added
        }
    }

    @MainActor private func summarize(_ item: Article) async {
        summaryErrors.remove(item.id)
        summarizingID = item.id
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "medium") ? .medium : .short

        if !expandedSummaries.contains(item.id) {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedSummaries.insert(item.id)
            }
            Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
        }

        var sawAny = false

        let stream = await ArticleSummarizer.shared.streamSummary(url: item.link, length: length, seedText: item.summary)
        for await partial in stream {
            sawAny = true
            inlineSummaries[item.id] = partial
            summaryErrors.remove(item.id)
            aiSummarized.insert(item.id)
        }
        if !sawAny {
            summaryErrors.insert(item.id)
        }
        summarizingID = nil
    }
}

// Modified struct FolderDetailView with refreshID property
struct FolderDetailView: View {
    let folder: Folder
    var refreshID: UUID = UUID()
    @EnvironmentObject private var store: FeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteFolder = false
    @StateObject private var vm = FolderItemsViewModel()
    @State private var webLink: WebLink?
    @State private var summarizingID: UUID?
    @State private var inlineSummaries: [UUID: String] = [:]
    @State private var expandedSummaries: Set<UUID> = []
    @State private var summaryErrors: Set<UUID> = []
    @State private var hasCachedText: Set<UUID> = [] // <-- Inserted here
    
    // Removed @State private var measuredSummaryHeights: [UUID: CGFloat] = [:]

    @AppStorage("summaryLength") private var summaryLengthRaw: String = "short"
    @State private var aiSummarized: Set<UUID> = []
    @State private var currentDay: Date? = nil
    @State private var suppressNextRowTap = false

    var body: some View {
        Group {
            if vm.isLoading && vm.items.isEmpty {
                ProgressView().controlSize(.large)
            } else if let error = vm.errorMessage, vm.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).multilineTextAlignment(.center)
                    Button("Retry") { Task { await vm.load(for: folder, feeds: store.feeds) } }
                }.padding()
            } else {
                List(vm.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)

                            Group {
                                let isError = summaryErrors.contains(item.id)
                                let aiSummary = inlineSummaries[item.id]

                                // Modified SummarizeButton per instruction wrapped in HStack with indicator
                                HStack(spacing: 6) {
                                    SummarizeButton(
                                        state: { () -> SummarizeButton.ButtonState in
                                            if summarizingID == item.id {
                                                return .generating
                                            }
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "medium") ? .medium : .short
                                            let hasCached = (aiSummary != nil) || ArticleSummarizer.hasCachedSummary(url: item.link, length: length)
                                            if hasCached {
                                                return .hasSummary(isExpanded: expandedSummaries.contains(item.id))
                                            } else {
                                                return .none
                                            }
                                        }()
                                    ) {
                                        // Toggle expand/collapse if summary exists; otherwise start summarization
                                        suppressNextRowTap = true
                                        let hasSummary = (aiSummary != nil)
                                        if hasSummary {
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "medium") ? .medium : .short
                                            if expandedSummaries.contains(item.id) {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    expandedSummaries.remove(item.id)
                                                }
                                                Task { await ArticleSummarizer.shared.setExpanded(false, url: item.link, length: length) }
                                            } else {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    expandedSummaries.insert(item.id)
                                                }
                                                Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
                                            }
                                        } else if summarizingID != item.id {
                                            Task { await summarize(item) }
                                        }
                                    }
                                    .disabled(isError)

                                    // Tiny indicator when readable text is cached for this article
                                    if hasCachedText.contains(item.id) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                            .accessibilityLabel("Cached text available")
                                    }
                                }

                                // Stable summary container prevents title jump by reserving height
                                ZStack(alignment: .topLeading) {
                                    if let aiSummary {
                                        CollapsibleText(text: aiSummary, isExpanded: expandedSummaries.contains(item.id))
                                    } else if isError {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                            Text("Summarization unavailable on this device.")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                // Removed .animation(.snappy(duration: 0.25), value: expandedSummaries.contains(item.id))
                            }

                            HStack(alignment: .center, spacing: 6) {
                                SourceBadge(iconURL: item.sourceIconURL, name: item.sourceTitle ?? "Source")
                                if let date = item.pubDate {
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
                        if let thumb = item.thumbnailURL {
                            ArticleThumbnailView(url: thumb)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DayAnchorReporter(date: item.pubDate, coordinateSpaceName: "FolderListScroll"))
                    .id(item.id)
                    .transaction { $0.disablesAnimations = false }
                }
                .listStyle(.plain)
                .transaction { $0.animation = nil }
                .refreshable { await vm.load(for: folder, feeds: store.feeds) }
                .coordinateSpace(name: "FolderListScroll")
                .task(id: vm.items.map { $0.id }) { preloadSummaries(for: vm.items) }
                .onChange(of: summaryLengthRaw) { _, _ in }
                .onPreferenceChange(DayAnchorsKey.self) { anchors in
                    guard !anchors.isEmpty else {
                        currentDay = nil
                        return
                    }
                    let sorted = anchors.sorted { a, b in
                        let aScore = (a.minY >= 0) ? a.minY : (100000 + abs(a.minY))
                        let bScore = (b.minY >= 0) ? b.minY : (100000 + abs(b.minY))
                        return aScore < bScore
                    }
                    let topDay = sorted.first?.dayStart
                    if currentDay != topDay {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            currentDay = topDay
                        }
                    }
                }
                .safeAreaInset(edge: .top) {
                    if let d = currentDay {
                        HStack {
                            FloatingDayChip(date: d)
                            Spacer()
                        }
                        .padding(.top, 4)
                        .padding(.leading, 8)
                        .padding(.trailing, 8)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingRefreshButton(isLoading: vm.isLoading) {
                Task { await vm.load(for: folder, feeds: store.feeds) }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 24)
        }
        .task(id: refreshID) { await vm.load(for: folder, feeds: store.feeds) }
        .navigationTitle(folder.name)
        .sheet(item: $webLink) { w in
            SafariView(url: w.url).ignoresSafeArea()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) { showingDeleteFolder = true } label: { Image(systemName: "trash") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("Summary Length") {
                        Button {
                            summaryLengthRaw = "short"
                        } label: {
                            HStack {
                                Text("Short")
                                if summaryLengthRaw == "short" { Image(systemName: "checkmark") }
                            }
                        }
                        Button {
                            summaryLengthRaw = "medium"
                        } label: {
                            HStack {
                                Text("Medium")
                                if summaryLengthRaw == "medium" { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    Button("Clear Summaries", role: .destructive) {
                        inlineSummaries.removeAll()
                        aiSummarized.removeAll()
                        expandedSummaries.removeAll()
                        summaryErrors.removeAll()
                        Task { await ArticleSummarizer.shared.clearCache() }
                    }
                    Button("Clear Article Text Cache", role: .destructive) {
                        Task { await ArticleTextCache.shared.clear() }
                    }
                } label: {
                    Image(systemName: "sparkles")
                }
            }
        }
        .alert("Delete Folder?", isPresented: $showingDeleteFolder) {
            Button("Delete", role: .destructive) {
                store.removeFolder(folder)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All sources will remain subscribed but will be removed from this folder.")
        }
    }

    private func preloadSummaries(for items: [Article]) {
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "medium") ? .medium : .short
        Task { @MainActor in
            var updated = inlineSummaries
            var expanded = expandedSummaries
            var cachedFlags = hasCachedText // <-- Added

            for item in items {
                if updated[item.id] == nil, let cached = await ArticleSummarizer.shared.cachedSummary(for: item.link, length: length) {
                    updated[item.id] = cached
                }
                // Restore expansion state from persisted store (default collapsed)
                if await ArticleSummarizer.shared.isExpanded(url: item.link, length: length) {
                    expanded.insert(item.id)
                } else {
                    expanded.remove(item.id)
                }
                // Update cached text indicator
                if await ArticleTextCache.shared.cachedText(for: item.link) != nil {
                    cachedFlags.insert(item.id)
                } else {
                    cachedFlags.remove(item.id)
                }
            }
            inlineSummaries = updated
            expandedSummaries = expanded
            hasCachedText = cachedFlags // <-- Added
        }
    }

    @MainActor private func summarize(_ item: Article) async {
        summaryErrors.remove(item.id)
        summarizingID = item.id
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "medium") ? .medium : .short

        if !expandedSummaries.contains(item.id) {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedSummaries.insert(item.id)
            }
            Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
        }

        var sawAny = false

        let stream = await ArticleSummarizer.shared.streamSummary(url: item.link, length: length, seedText: item.summary)
        for await partial in stream {
            sawAny = true
            inlineSummaries[item.id] = partial
            summaryErrors.remove(item.id)
            aiSummarized.insert(item.id)
        }
        if !sawAny {
            summaryErrors.insert(item.id)
        }
        summarizingID = nil
    }
}

// Modified struct AllArticlesView with refreshID property
struct AllArticlesView: View {
    @EnvironmentObject private var store: FeedStore
    var refreshID: UUID = UUID()
    @StateObject private var vm = FolderItemsViewModel()
    @State private var webLink: WebLink?
    @State private var summarizingID: UUID?
    @State private var inlineSummaries: [UUID: String] = [:]
    @State private var expandedSummaries: Set<UUID> = []
    @State private var summaryErrors: Set<UUID> = []
    @State private var hasCachedText: Set<UUID> = [] // <-- Inserted here
    
    // Removed @State private var measuredSummaryHeights: [UUID: CGFloat] = [:]

    @AppStorage("summaryLength") private var summaryLengthRaw: String = "short"
    @State private var aiSummarized: Set<UUID> = []
    @State private var currentDay: Date? = nil
    @State private var suppressNextRowTap = false

    var body: some View {
        Group {
            if vm.isLoading && vm.items.isEmpty {
                ProgressView().controlSize(.large)
            } else if let error = vm.errorMessage, vm.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).multilineTextAlignment(.center)
                    Button("Retry") { Task { await vm.loadAll(feeds: store.feeds) } }
                }.padding()
            } else {
                List(vm.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)

                            Group {
                                let isError = summaryErrors.contains(item.id)
                                let aiSummary = inlineSummaries[item.id]

                                // Modified SummarizeButton per instruction wrapped in HStack with indicator
                                HStack(spacing: 6) {
                                    SummarizeButton(
                                        state: { () -> SummarizeButton.ButtonState in
                                            if summarizingID == item.id {
                                                return .generating
                                            }
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "medium") ? .medium : .short
                                            let hasCached = (aiSummary != nil) || ArticleSummarizer.hasCachedSummary(url: item.link, length: length)
                                            if hasCached {
                                                return .hasSummary(isExpanded: expandedSummaries.contains(item.id))
                                            } else {
                                                return .none
                                            }
                                        }()
                                    ) {
                                        // Toggle expand/collapse if summary exists; otherwise start summarization
                                        suppressNextRowTap = true
                                        let hasSummary = (aiSummary != nil)
                                        if hasSummary {
                                            let length: ArticleSummarizer.Length = (summaryLengthRaw == "medium") ? .medium : .short
                                            if expandedSummaries.contains(item.id) {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    expandedSummaries.remove(item.id)
                                                }
                                                Task { await ArticleSummarizer.shared.setExpanded(false, url: item.link, length: length) }
                                            } else {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    expandedSummaries.insert(item.id)
                                                }
                                                Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
                                            }
                                        } else if summarizingID != item.id {
                                            Task { await summarize(item) }
                                        }
                                    }
                                    .disabled(isError)

                                    // Tiny indicator when readable text is cached for this article
                                    if hasCachedText.contains(item.id) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                            .accessibilityLabel("Cached text available")
                                    }
                                }

                                // Stable summary container prevents title jump by reserving height
                                ZStack(alignment: .topLeading) {
                                    if let aiSummary {
                                        CollapsibleText(text: aiSummary, isExpanded: expandedSummaries.contains(item.id))
                                    } else if isError {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                            Text("Summarization unavailable on this device.")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                // Removed .animation(.snappy(duration: 0.25), value: expandedSummaries.contains(item.id))
                            }

                            HStack(alignment: .center, spacing: 6) {
                                SourceBadge(iconURL: item.sourceIconURL, name: item.sourceTitle ?? "Source")
                                if let date = item.pubDate {
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
                        if let thumb = item.thumbnailURL {
                            ArticleThumbnailView(url: thumb)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DayAnchorReporter(date: item.pubDate, coordinateSpaceName: "AllListScroll"))
                    .id(item.id)
                    .transaction { $0.disablesAnimations = false }
                }
                .listStyle(.plain)
                .transaction { $0.animation = nil }
                .refreshable { await vm.loadAll(feeds: store.feeds) }
                .coordinateSpace(name: "AllListScroll")
                .task(id: vm.items.map { $0.id }) { preloadSummaries(for: vm.items) }
                .onChange(of: summaryLengthRaw) { _, _ in }
                .onPreferenceChange(DayAnchorsKey.self) { anchors in
                    guard !anchors.isEmpty else {
                        currentDay = nil
                        return
                    }
                    let sorted = anchors.sorted { a, b in
                        let aScore = (a.minY >= 0) ? a.minY : (100000 + abs(a.minY))
                        let bScore = (b.minY >= 0) ? b.minY : (100000 + abs(b.minY))
                        return aScore < bScore
                    }
                    let topDay = sorted.first?.dayStart
                    if currentDay != topDay {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            currentDay = topDay
                        }
                    }
                }
                .safeAreaInset(edge: .top) {
                    if let d = currentDay {
                        HStack {
                            FloatingDayChip(date: d)
                            Spacer()
                        }
                        .padding(.top, 4)
                        .padding(.leading, 8)
                        .padding(.trailing, 8)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingRefreshButton(isLoading: vm.isLoading) {
                Task { await vm.loadAll(feeds: store.feeds) }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 24)
        }
        .task(id: refreshID) { await vm.loadAll(feeds: store.feeds) }
        .navigationTitle("All Articles")
        .sheet(item: $webLink) { w in
            SafariView(url: w.url).ignoresSafeArea()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("Summary Length") {
                        Button {
                            summaryLengthRaw = "short"
                        } label: {
                            HStack {
                                Text("Short")
                                if summaryLengthRaw == "short" { Image(systemName: "checkmark") }
                            }
                        }
                        Button {
                            summaryLengthRaw = "medium"
                        } label: {
                            HStack {
                                Text("Medium")
                                if summaryLengthRaw == "medium" { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    Button("Clear Summaries", role: .destructive) {
                        inlineSummaries.removeAll()
                        aiSummarized.removeAll()
                        expandedSummaries.removeAll()
                        summaryErrors.removeAll()
                        Task { await ArticleSummarizer.shared.clearCache() }
                    }
                    Button("Clear Article Text Cache", role: .destructive) {
                        Task { await ArticleTextCache.shared.clear() }
                    }
                } label: {
                    Image(systemName: "sparkles")
                }
            }
        }
    }

    private func preloadSummaries(for items: [Article]) {
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "medium") ? .medium : .short
        Task { @MainActor in
            var updated = inlineSummaries
            var expanded = expandedSummaries
            var cachedFlags = hasCachedText // <-- Added

            for item in items {
                if updated[item.id] == nil, let cached = await ArticleSummarizer.shared.cachedSummary(for: item.link, length: length) {
                    updated[item.id] = cached
                }
                // Restore expansion state from persisted store (default collapsed)
                if await ArticleSummarizer.shared.isExpanded(url: item.link, length: length) {
                    expanded.insert(item.id)
                } else {
                    expanded.remove(item.id)
                }
                // Update cached text indicator
                if await ArticleTextCache.shared.cachedText(for: item.link) != nil {
                    cachedFlags.insert(item.id)
                } else {
                    cachedFlags.remove(item.id)
                }
            }
            inlineSummaries = updated
            expandedSummaries = expanded
            hasCachedText = cachedFlags // <-- Added
        }
    }

    @MainActor private func summarize(_ item: Article) async {
        summaryErrors.remove(item.id)
        summarizingID = item.id
        let length: ArticleSummarizer.Length = (summaryLengthRaw == "medium") ? .medium : .short

        if !expandedSummaries.contains(item.id) {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedSummaries.insert(item.id)
            }
            Task { await ArticleSummarizer.shared.setExpanded(true, url: item.link, length: length) }
        }

        var sawAny = false

        let stream = await ArticleSummarizer.shared.streamSummary(url: item.link, length: length, seedText: item.summary)
        for await partial in stream {
            sawAny = true
            inlineSummaries[item.id] = partial
            summaryErrors.remove(item.id)
            aiSummarized.insert(item.id)
        }
        if !sawAny {
            summaryErrors.insert(item.id)
        }
        summarizingID = nil
    }
}

// MARK: - Add Source UI (auto-favicon)
struct AddFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FeedStore
    @State private var title: String = ""
    @State private var urlString: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var onAdd: (Source) -> Void
    private let faviconService = FaviconService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title (optional)", text: $title)
                    TextField("Source URL (https://…)", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Add Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: add) {
                        if isSaving { ProgressView() } else { Text("Add") }
                    }.disabled(!isValidURL || isSaving)
                }
            }
        }
    }

    var isValidURL: Bool { URL(string: urlString)?.scheme?.hasPrefix("http") == true }

    func add() {
        if let url = URL(string: urlString) {
            isSaving = true; errorMessage = nil
            Task {
                let icon = await faviconService.resolveIcon(for: url)
                let feed = Feed(title: title.isEmpty ? (url.host ?? "Feed") : title, url: url, iconURL: icon)
                onAdd(feed)
                isSaving = false
                dismiss()
            }
        } else {
            isSaving = false
            errorMessage = "Invalid URL"
        }
    }
}

// MARK: - Add Folder UI
struct AddFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    var onAdd: (Folder) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Folder name", text: $name)
                }
            }
            .navigationTitle("Add Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onAdd(Folder(name: trimmed))
                        dismiss()
                    } label: {
                        Text("Add")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Safari wrapper
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

// MARK: - WebLink for sheet(item:)
struct WebLink: Identifiable { let id = UUID(); let url: URL }

// MARK: - Floating Day Indicator support
struct DayAnchor: Equatable {
    let dayStart: Date
    let minY: CGFloat
}

struct DayAnchorsKey: PreferenceKey {
    static var defaultValue: [DayAnchor] = []
    static func reduce(value: inout [DayAnchor], nextValue: () -> [DayAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

// Inserted helper view for per-row day anchor reporting
struct DayAnchorReporter: View {
    let date: Date?
    let coordinateSpaceName: String
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: DayAnchorsKey.self, value: {
                    guard let date else { return [] }
                    let dayStart = Calendar.current.startOfDay(for: date)
                    let minY = proxy.frame(in: .named(coordinateSpaceName)).minY
                    return [DayAnchor(dayStart: dayStart, minY: minY)]
                }())
        }
    }
}

struct FloatingDayChip: View {
    let date: Date
    var body: some View {
        Text(dayLabel(for: date))
            .font(.callout.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.secondary.opacity(0.2))
            )
    }

    private func dayLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: date)
    }
}

// MARK: - Concurrency control gate (semaphore-like)
actor ConcurrencyGate {
    private let limit: Int
    private var current: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = max(1, limit) }

    func enter() async {
        if current < limit {
            current += 1
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
        // Woken up by leave(); a slot is now ours
        current += 1
    }

    func leave() {
        if !waiters.isEmpty {
            let cont = waiters.removeFirst()
            cont.resume()
        } else {
            current = max(0, current - 1)
        }
    }

    func reset() {
        // Clear all waiters and release the counter so a new run starts fresh
        for cont in waiters {
            cont.resume()
        }
        waiters.removeAll()
        current = 0
    }

    // Convenience helper to avoid calling leave() from non-async contexts
    func withPermit<T>(operation: () async throws -> T) async rethrows -> T {
        await enter()
        defer { leave() }
        return try await operation()
    }
}

// MARK: - App entry
struct ContentView: View {
    @StateObject private var store = FeedStore()
    @State private var selectedSource: Source?
    @State private var showingAdd = false
    @State private var showingAddFolder = false
    @State private var movingSource: Source?
    @State private var showingMoveDialog = false
    @State private var refreshID = UUID()
    @State private var isRefreshingAll = false
    @State private var refreshTotal: Int = 0
    @State private var refreshCompleted: Int = 0
    @State private var refreshArticlesCachedThisRun: Int = 0
    @State private var refreshArticlesSkippedThisRun: Int = 0
    @State private var currentRefreshRunID = UUID()
    @State private var cooldownUntil: Date? = nil

    private let refreshService = FeedService()

    // Concurrency limits and gates for controlled caching
    private let maxConcurrentFeeds = 2
    private let maxPrefetchPerFeed = 6
    private let maxConcurrentArticlePrefetch = 1
    private let interBatchDelayNs: UInt64 = 150_000_000 // 150ms

    private let feedGate = ConcurrencyGate(limit: 2)
    private let articleGate = ConcurrencyGate(limit: 3)

    private func refreshAll() async {
        let runID = currentRefreshRunID
        let feeds = store.feeds
        let snapshotFeeds = feeds
        if Task.isCancelled { return }
        await MainActor.run {
            // Initialize counters for new run
            refreshTotal = feeds.count
            refreshCompleted = 0
            refreshArticlesCachedThisRun = 0
            refreshArticlesSkippedThisRun = 0
        }

        await withTaskGroup(of: Void.self) { group in
            for feed in snapshotFeeds {
                group.addTask {
                    if Task.isCancelled { return }
                    await feedGate.withPermit {
                        defer {
                            Task { @MainActor in
                                if isRefreshingAll && runID == currentRefreshRunID {
                                    refreshCompleted += 1
                                }
                            }
                        }
                        do {
                            let items = try await refreshService.loadItems(from: feed.url)
                            try Task.checkCancellation()
                            if Task.isCancelled { return }

                            // Limit how many we prefetch per feed
                            let limited = Array(items.prefix(maxPrefetchPerFeed))

                            // Process in small batches to avoid spikes
                            let batchSize = max(1, maxConcurrentArticlePrefetch)
                            var index = 0
                            while index < limited.count {
                                if Task.isCancelled { return }
                                let end = min(index + batchSize, limited.count)
                                let batch = limited[index..<end]

                                await withTaskGroup(of: Void.self) { inner in
                                    for item in batch {
                                        inner.addTask {
                                            if Task.isCancelled { return }
                                            if Task.isCancelled { return }
                                            await articleGate.withPermit {
                                                // Skip if already cached
                                                if await ArticleTextCache.shared.cachedText(for: item.link) != nil {
                                                    await MainActor.run { refreshArticlesSkippedThisRun += 1 }
                                                    return
                                                }
                                                if Task.isCancelled { return }
                                                do {
                                                    try Task.checkCancellation()
                                                    try await withTimeout(5.0) {
                                                        try Task.checkCancellation()
                                                        let html = try await ArticleSummarizer.shared.fetchHTML(url: item.link)
                                                        try Task.checkCancellation()
                                                        let limitedHTML = String(html.prefix(160_000))
                                                        let text = ArticleSummarizer.shared.extractReadableText(from: limitedHTML)
                                                        try Task.checkCancellation()
                                                        if !text.isEmpty {
                                                            await ArticleTextCache.shared.storeText(text, for: item.link)
                                                            await MainActor.run { refreshArticlesCachedThisRun += 1 }
                                                        }
                                                    }
                                                } catch {
                                                    // Ignore per-item errors (including timeouts)
                                                }
                                            }
                                        }
                                    }
                                    for await _ in inner { }
                                    if Task.isCancelled { return }
                                }

                                // Small pause between batches to keep UI responsive
                                try? await Task.sleep(nanoseconds: interBatchDelayNs)
                                try Task.checkCancellation()
                                if Task.isCancelled { return }
                                index = end
                            }
                        } catch {
                            // Ignore individual failures for the global refresh
                        }
                    }
                }
            }
            for await _ in group { }
        }
    }

    private func withTimeout<T>(_ seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            guard let result = try await group.next() else {
                group.cancelAll()
                throw URLError(.unknown)
            }
            group.cancelAll()
            return result
        }
    }

    @ViewBuilder private var sidebar: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                Section("Folders") {
                    NavigationLink {
                        AllArticlesView(refreshID: refreshID)
                            .environmentObject(store)
                    } label: {
                        Label("All Articles", systemImage: "newspaper.fill")
                            .contentShape(Rectangle())
                    }
                    // Removed .simultaneousGesture to fix tap target and refresh bug

                    ForEach(store.folders) { folder in
                        NavigationLink {
                            FolderDetailView(folder: folder, refreshID: refreshID)
                                .environmentObject(store)
                        } label: {
                            HStack {
                                Label(folder.name, systemImage: "folder")
                                Spacer()
                                Text("\(store.feeds.filter { $0.folderID == folder.id }.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        // Removed .simultaneousGesture to fix tap target and refresh bug
                        .swipeActions {
                            Button(role: .destructive) {
                                store.removeFolder(folder)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                Section("Sources") {
                    ForEach(store.feeds) { source in
                        NavigationLink {
                            FeedDetailView(source: source, refreshID: refreshID)
                        } label: {
                            HStack(spacing: 12) {
                                FeedIconView(iconURL: source.iconURL)
                                Text(source.title)
                            }
                            .contentShape(Rectangle())
                        }
                        // Removed .simultaneousGesture to fix tap target and refresh bug
                        .contextMenu {
                            Button("Refresh Icon") {
                                Task { await store.refreshIcon(for: source) }
                            }
                            Menu("Move to Folder") {
                                ForEach(store.folders) { folder in
                                    Button(folder.name) {
                                        store.assign(source, to: folder)
                                    }
                                }
                                if source.folderID != nil {
                                    Button("Remove from Folder") {
                                        store.assign(source, to: nil)
                                    }
                                }
                            }
                        }
                        .swipeActions {
                            if source.folderID != nil {
                                Button("Remove", role: .destructive) {
                                    store.assign(source, to: nil)
                                }
                            }
                            Button("Move") {
                                movingSource = source
                                showingMoveDialog = true
                            }
                            Button("Delete", role: .destructive) {
                                if let idx = store.feeds.firstIndex(where: { $0.id == source.id }) {
                                    store.feeds.remove(at: idx)
                                    if selectedSource?.id == source.id {
                                        selectedSource = store.feeds.first
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("VibeRSS")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingAddFolder = true } label: { Image(systemName: "folder.badge.plus") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddFeedView { newSource in
                    store.feeds.append(newSource)
                    selectedSource = newSource
                }
                .environmentObject(store)
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingAddFolder) {
                AddFolderView { newFolder in
                    store.folders.append(newFolder)
                }
                .presentationDetents([.medium])
            }
            .confirmationDialog("Move to Folder", isPresented: $showingMoveDialog, presenting: movingSource) { source in
                ForEach(store.folders) { folder in
                    Button(folder.name) {
                        store.assign(source, to: folder)
                    }
                }
                if source.folderID != nil {
                    Button("Remove from Folder", role: .destructive) {
                        store.assign(source, to: nil)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { source in
                Text("Choose a folder for \(source.title)")
            }

            FloatingRefreshButton(isLoading: isRefreshingAll) {
                // Cooldown: prevent immediate re-entry for 1.5s after a run
                if let until = cooldownUntil, until > Date() { return }
                guard !isRefreshingAll else { return }
                isRefreshingAll = true
                currentRefreshRunID = UUID()
                let localRunID = currentRefreshRunID
                Task {
                    await feedGate.reset()
                    await articleGate.reset()
                    await MainActor.run {
                        // Initialize counters for new run
                        refreshCompleted = 0
                        refreshTotal = store.feeds.count
                        refreshArticlesCachedThisRun = 0
                        refreshArticlesSkippedThisRun = 0
                    }
                    do {
                        try await withTimeout(30.0) { await refreshAll() }
                    } catch {
                        await feedGate.reset()
                        await articleGate.reset()
                        // Watchdog fired; continue to reset UI state
                    }
                    // Bump ID so destination views update
                    await MainActor.run {
                        // Bump ID so destination views update
                        refreshID = UUID()
                        // Mark refresh finished and immediately reset counters
                        isRefreshingAll = false
                        refreshCompleted = 0
                        refreshTotal = 0
                        refreshArticlesCachedThisRun = 0
                        refreshArticlesSkippedThisRun = 0
                        // Set cooldown 1.5s to avoid overlapping runs
                        cooldownUntil = Date().addingTimeInterval(1.5)
                    }
                    // Removed delayed reset and second MainActor.run block
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 24)

            // Bottom linear progress bar for global refresh
            VStack {
                Spacer()
                if isRefreshingAll {
                    HStack(spacing: 10) {
                        ProgressView(value: Double(refreshCompleted), total: Double(refreshTotal))
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Refreshing feeds: \(refreshCompleted)/\(refreshTotal)")
                            Text("Cached (new): \(refreshArticlesCachedThisRun)")
                            Text("Skipped (already cached): \(refreshArticlesSkippedThisRun)")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(Color.secondary.opacity(0.2))
                    )
                    .padding(.bottom, 8)
                }
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var detailView: some View {
        if let source = selectedSource ?? store.feeds.first {
            FeedDetailView(source: source, refreshID: refreshID)
        } else {
            ContentPlaceholder()
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationDestination(for: Source.self) { source in
            FeedDetailView(source: source, refreshID: refreshID)
        }
        .onAppear { selectedSource = store.feeds.first; store.backfillIcons() }
    }
}

@main
struct VibeRSSApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

// Inserted actor ArticleTextCache immediately above MARK: - ArticleSummarizer
actor ArticleTextCache {
    static let shared = ArticleTextCache()

    private var cache: [String: String] = [:] // key: url.absoluteString
    private let storeKey = "viberss.articleTextCache"
    private var saveDebounceTask: Task<Void, Never>? = nil

    init() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = dict
        }
    }

    func cachedText(for url: URL) -> String? {
        cache[url.absoluteString]
    }

    func storeText(_ text: String, for url: URL) {
        cache[url.absoluteString] = text
        debounceSave()
    }

    func clear() {
        cache.removeAll()
        UserDefaults.standard.removeObject(forKey: storeKey)
    }

    private func debounceSave() {
        saveDebounceTask?.cancel()
        let snapshot = cache
        saveDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: storeKey)
            }
        }
    }
}

// MARK: - ArticleSummarizer
actor ArticleSummarizer {
    static let shared = ArticleSummarizer()

    enum Length {
        case short, medium
    }

    private var cache: [String: String] = [:] // key: "<url>#<length>"
    private let cacheStoreKey = "viberss.summaryCache"
    private let expandedStoreKey = "viberss.summaryExpanded"
    private var expandedState: Set<String> = [] // keys: "<url>#<length>"

    private var saveCacheDebounceTask: Task<Void, Never>? = nil
    private var saveExpandedDebounceTask: Task<Void, Never>? = nil

    // Nonisolated hint to quickly know if a cached summary likely exists (read-only from UserDefaults)
    nonisolated static func hasCachedSummary(url: URL, length: Length) -> Bool {
        // Reconstruct the key format used for storage
        let len = (length == .medium) ? "medium" : "short"
        let key = url.absoluteString + "#" + len
        // Read the serialized cache dictionary directly (avoids awaiting the actor)
        if let data = UserDefaults.standard.data(forKey: "viberss.summaryCache"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            return dict[key] != nil
        }
        return false
    }

    init() {
        cache = Self.loadCacheFromDefaults()
        expandedState = Self.loadExpandedFromDefaults()
    }

    private static func loadCacheFromDefaults() -> [String: String] {
        if let data = UserDefaults.standard.data(forKey: "viberss.summaryCache"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            return dict
        }
        return [:]
    }

    private static func loadExpandedFromDefaults() -> Set<String> {
        if let data = UserDefaults.standard.data(forKey: "viberss.summaryExpanded"),
           let set = try? JSONDecoder().decode(Set<String>.self, from: data) {
            return set
        }
        return []
    }

    private func saveCache() {
        saveCacheDebounceTask?.cancel()
        guard let data = try? JSONEncoder().encode(cache) else { return }
        saveCacheDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            UserDefaults.standard.set(data, forKey: cacheStoreKey)
        }
    }

    private func saveExpanded() {
        saveExpandedDebounceTask?.cancel()
        guard let data = try? JSONEncoder().encode(expandedState) else { return }
        saveExpandedDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            UserDefaults.standard.set(data, forKey: expandedStoreKey)
        }
    }

    func clearCache() {
        cache.removeAll()
        expandedState.removeAll()
        UserDefaults.standard.removeObject(forKey: cacheStoreKey)
        UserDefaults.standard.removeObject(forKey: expandedStoreKey)
    }

    func cachedSummary(for url: URL, length: Length) -> String? {
        let key = makeCacheKey(url: url, length: length)
        return cache[key]
    }

    func isExpanded(url: URL, length: Length) async -> Bool {
        expandedState.contains(makeCacheKey(url: url, length: length))
    }

    func setExpanded(_ expanded: Bool, url: URL, length: Length) async {
        let key = makeCacheKey(url: url, length: length)
        if expanded {
            expandedState.insert(key)
        } else {
            expandedState.remove(key)
        }
        saveExpanded()
    }

    private func makeCacheKey(url: URL, length: Length) -> String {
        let len = (length == .medium) ? "medium" : "short"
        return url.absoluteString + "#" + len
    }

    func streamSummary(url: URL, length: Length, seedText: String?) async -> AsyncStream<String> {
        AsyncStream { continuation in
            let worker = Task {
                let key = makeCacheKey(url: url, length: length)
                if let cached = cache[key] {
                    continuation.yield(cached)
                    continuation.finish()
                    return
                }
                if Task.isCancelled { continuation.finish(); return }

#if canImport(FoundationModels)
                let model = SystemLanguageModel.default
                guard case .available = model.availability else {
                    continuation.finish()
                    return
                }

                // Try preloaded readable text first; otherwise fetch and extract
                let cachedText = await ArticleTextCache.shared.cachedText(for: url)
                let baseText: String
                if let cachedText, !cachedText.isEmpty {
                    baseText = String(cachedText.prefix(250_000))
                } else {
                    guard let html = try? await fetchHTML(url: url) else {
                        continuation.finish()
                        return
                    }
                    let limitedHTML = String(html.prefix(250_000))
                    let extracted = extractReadableText(from: limitedHTML)
                    if extracted.isEmpty {
                        continuation.finish()
                        return
                    }
                    baseText = extracted
                    await ArticleTextCache.shared.storeText(extracted, for: url)
                }

                let instructions: String = {
                    switch length {
                    case .short:
                        return "Summarize for busy readers in 1–3 sentences (<80 words). Focus on key facts. No fluff. Avoid repetition."
                    case .medium:
                        return "Summarize for busy readers in 3–6 sentences (<200 words). Focus on key facts, context, implications. No fluff. Avoid repetition."
                    }
                }()

                let session = LanguageModelSession(instructions: instructions)

                // Build a prompt using extracted text, optionally including a small portion of the feed's seed text for context.
                var prompt = "Summarize this article:\n\n"
                if let seed = seedText?.trimmingCharacters(in: .whitespacesAndNewlines), !seed.isEmpty {
                    let s = String(seed.prefix(900))
                    prompt += "Preview/context from feed:\n\(s)\n\n"
                }
                let body = String(baseText.prefix(12_000))
                prompt += body

                do {
                    let stream = session.streamResponse(to: prompt, generating: InlineSummary.self)
                    var finalText: String = ""
                    var revealedCount: Int = 0
                    let step = 2
                    let stepDelay: UInt64 = 30_000_000 // 30 ms

                    for try await partial in stream {
                        if Task.isCancelled { continuation.finish(); return }
                        guard let t = partial.content.text, !t.isEmpty else { continue }
                        finalText = t

                        // Skip if we've already revealed up to this length
                        if t.count <= revealedCount { continue }

                        // Reveal the new delta in small steps to feel faster
                        var target = min(revealedCount + step, t.count)
                        while target < t.count {
                            let idx = t.index(t.startIndex, offsetBy: target)
                            let prefix = String(t[..<idx])
                            continuation.yield(prefix)
                            revealedCount = target
                            // Small delay to simulate typing while keeping UI responsive
                            try? await Task.sleep(nanoseconds: stepDelay)
                            if Task.isCancelled { continuation.finish(); return }
                            target = min(revealedCount + step, t.count)
                        }

                        // Ensure we yield the full current text for this partial
                        continuation.yield(t)
                        revealedCount = t.count
                    }

                    if !finalText.isEmpty {
                        self.cache[key] = finalText
                        self.saveCache()
                    }
                    continuation.finish()
                    return
                } catch {
                    continuation.finish()
                    return
                }
#else
                continuation.finish()
#endif
            }
            continuation.onTermination = { _ in
                worker.cancel()
            }
        }
    }

    func fetchHTML(url: URL) async throws -> String {
        try Task.checkCancellation()
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 3)
        let (data, _) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated func extractReadableText(from html: String) -> String {
        if html.isEmpty { return "" }
        if Task.isCancelled { return "" }
        // Work on a limited slice to speed up regex processing
        var s = String(html.prefix(200_000))
        if Task.isCancelled { return "" }
        // Remove comments
        s = s.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)

        // Prefer <article> content if present
        if let range = s.range(of: "<article[\\n\\r\\s\\S]*?</article>", options: .regularExpression) {
            s = String(s[range])
        }
        if Task.isCancelled { return "" }

        // Remove common boilerplate blocks
        let blocks = ["nav", "header", "footer", "aside"]
        for tag in blocks {
            if let regex = try? NSRegularExpression(pattern: "<" + tag + "[\\n\\r\\s\\S]*?</" + tag + ">", options: [.caseInsensitive]) {
                s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
            }
        }

        // Remove scripts and styles
        if let regex = try? NSRegularExpression(pattern: "<script[\\n\\r\\s\\S]*?</script>", options: [.caseInsensitive]) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
        }
        if Task.isCancelled { return "" }
        if let regex = try? NSRegularExpression(pattern: "<style[\\n\\r\\s\\S]*?</style>", options: [.caseInsensitive]) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
        }

        // Strip all tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
        }
        if Task.isCancelled { return "" }

        // Decode HTML entities roughly by letting AttributedString handle some
        let attr = try? AttributedString(markdown: s)
        let plain = attr?.description ?? s

        // Collapse whitespace
        let collapsed = plain.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression, range: nil)
        if Task.isCancelled { return "" }
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func chunk(text: String, size: Int, overlap: Int = 0) -> [String] {
        guard !text.isEmpty, size > 0 else { return [] }
        var result: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            let slice = String(text[start..<end])
            result.append(slice)
            if end == text.endIndex { break }
            let nextStart = overlap > 0 ? text.index(end, offsetBy: -min(overlap, size), limitedBy: text.startIndex) ?? end : end
            start = nextStart
        }
        return result
    }
}


