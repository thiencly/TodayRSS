// FaviconService.swift
// Purpose: Resolve a site's icon (favicon / apple-touch-icon) for a given feed URL.
//
// What it does:
// - Derives a base site URL from a feed URL (e.g., https://example.com from https://example.com/feed.xml)
// - Looks for icon declarations in the site's HTML (<link rel="icon" ...>, <link rel="apple-touch-icon" ...>)
// - Tries common icon paths (/favicon.ico, /apple-touch-icon.png, etc.) as fallbacks
// - Uses HEAD/GET requests to verify that candidate icon URLs exist
// - Includes simple fallbacks like apex domain and www. variants
//
// How to use:
// - Create and call `await FaviconService().resolveIcon(for: feedURL)`
// - Returns a URL to an icon if found, otherwise nil
//
// Notes:
// - Implemented as an actor to keep network usage serialized where needed.
// - This file is UI-agnostic and safe to use anywhere in the app.



import Foundation
import SwiftUI


actor FaviconService {
    func resolveIcon(for feedURL: URL) async -> URL? {
        // Derive site base from feed URL
        guard var comps = URLComponents(url: feedURL, resolvingAgainstBaseURL: false) else { return nil }
        comps.path = "/"; comps.query = nil; comps.fragment = nil
        guard let base = comps.url else { return nil }

        // Compute apex domain base (simple heuristic: drop first label if 3+ labels)
        var apexBase: URL? = nil
        if let host = comps.host {
            let parts = host.split(separator: ".")
            if parts.count >= 3 {
                let apexHost = parts.suffix(2).joined(separator: ".")
                var apexComps = comps
                apexComps.host = apexHost
                apexBase = apexComps.url
            }
        }

        // Prepare a www. variant of the host as another fallback
        var wwwBase: URL? = nil
        if let host = comps.host, !host.lowercased().hasPrefix("www.") {
            var wwwComps = comps
            wwwComps.host = "www." + host
            wwwBase = wwwComps.url
        }

        // Helper that runs HTML scan then common paths against a given base
        func tryResolve(from base: URL) async -> URL? {
            if let html = await fetchHTML(from: base) {
                let hrefs = iconLinkCandidates(in: html)
                for href in hrefs {
                    if let icon = URL(string: href, relativeTo: base), await urlExists(icon) {
                        return icon.absoluteURL
                    }
                }
            }
            for candidate in commonIconURLs(for: base) {
                if await urlExists(candidate) {
                    return candidate.absoluteURL
                }
            }
            return nil
        }

        // 1) Try the direct base
        if let found = await tryResolve(from: base) { return found }

        // 2) Try apex base if applicable
        if let apex = apexBase, apex != base, let found = await tryResolve(from: apex) { return found }

        // 3) Try the feed URL page itself (icons may be declared there)
        if let found = await tryResolve(from: feedURL) { return found }

        // 4) Try www. variant if applicable
        if let www = wwwBase, www != base, let found = await tryResolve(from: www) { return found }

        return nil
    }

    private func absolute(_ url: URL) -> URL { url }

    private func urlExists(_ url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 5
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        do {
            try Task.checkCancellation()
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse { return (200..<400).contains(http.statusCode) }
        } catch {}
        // Some servers reject HEAD—fallback to GET small
        do {
            try Task.checkCancellation()
            var getReq = URLRequest(url: url)
            getReq.timeoutInterval = 5
            getReq.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            let (_, resp) = try await URLSession.shared.data(for: getReq)
            if let http = resp as? HTTPURLResponse { return (200..<400).contains(http.statusCode) }
        } catch {}
        return false
    }

    private func fetchHTML(from url: URL) async -> String? {
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 6
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            try Task.checkCancellation()
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return String(data: data, encoding: .utf8)
        } catch { return nil }
    }

    private func commonIconURLs(for base: URL) -> [URL] {
        let paths = [
            "/apple-touch-icon.png",
            "/apple-touch-icon-180x180.png",
            "/apple-touch-icon-152x152.png",
            "/apple-touch-icon-120x120.png",
            "/apple-touch-icon-precomposed.png",
            "/favicon-196x196.png",
            "/android-chrome-192x192.png",
            "/favicon-96x96.png",
            "/favicon-64x64.png",
            "/favicon-48x48.png",
            "/favicon-32x32.png",
            "/favicon-16x16.png",
            "/favicon.png",
            "/favicon.ico",
            "/favicon.svg"
        ]
        return paths.compactMap { URL(string: $0, relativeTo: base) }
    }

    private func iconLinkCandidates(in html: String) -> [String] {
        // Find all <link ...> tags that declare an icon rel, then extract href and sizes
        let linkPattern = "<link[^>]*?rel=[\"'][^\"']*(?:icon|apple-touch-icon|shortcut icon|mask-icon)[^\"']*[\"'][^>]*>"
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
            // Prefer apple-touch and PNG formats slightly
            let hrefLower = hrefStr.lowercased()
            var formatBoost = 0
            if (tag as String).range(of: "apple-touch-icon", options: .caseInsensitive) != nil {
                formatBoost += 100
            } else if hrefLower.hasSuffix(".png") {
                formatBoost += 20
            }
            sizeValue += formatBoost

            candidates.append(Candidate(href: hrefStr, size: sizeValue))
        }

        // Sort by size descending and return hrefs
        return candidates.sorted { $0.size > $1.size }.map { $0.href }
    }
}
