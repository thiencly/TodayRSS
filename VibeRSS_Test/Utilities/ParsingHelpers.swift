//
//  ParsingHelpers.swift
//  VibeRSS_Test
//
//  Created by You on Today.
//
// FILE: Utilities/ParsingHelpers.swift
// PURPOSE: Small helpers used by RSS/Atom parsers (string trimming, HTML cleanup, image URL extraction, date formats)
// SAFE TO EDIT: Yes, keep APIs stable if parsers rely on them.

import Foundation

// MARK: - String helpers

extension String {
    // Trims common whitespace and newlines
    func vr_trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Very lightweight HTML cleanup:
    // - Strips basic tags like <...>
    // - Replaces multiple whitespace with a single space
    // - Trims ends
    func vr_trimmedHTML() -> String {
        // Remove tags like <p>, </a>, <img ...>, etc.
        let withoutTags = self.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode common HTML entities (very small set; expand as needed)
        let decoded = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        // Collapse repeated whitespace
        let collapsed = decoded.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return collapsed.vr_trimmed()
    }
}

// MARK: - Image URL extraction

// Attempts to find the first image URL in a chunk of HTML.
// - Looks for <img src="..."> first
// - Falls back to common Open Graph tags (og:image)
// - Returns an absolute URL if possible (resolves relative URLs using base)
func extractFirstImageURL(from html: String, relativeTo base: URL) -> URL? {
    // 1) <img src="...">
    if let imgSrc = firstMatch(in: html, pattern: #"<img[^>]*\ssrc\s*=\s*["']([^"']+)["']"#) {
        if let url = URL(string: imgSrc, relativeTo: base)?.absoluteURL {
            return url
        }
    }

    // 2) <meta property="og:image" content="...">
    if let ogImage = firstMatch(in: html, pattern: #"<meta[^>]*property\s*=\s*["']og:image["'][^>]*content\s*=\s*["']([^"']+)["']"#) {
        if let url = URL(string: ogImage, relativeTo: base)?.absoluteURL {
            return url
        }
    }

    // 3) <meta name="twitter:image" content="...">
    if let twitterImage = firstMatch(in: html, pattern: #"<meta[^>]*name\s*=\s*["']twitter:image["'][^>]*content\s*=\s*["']([^"']+)["']"#) {
        if let url = URL(string: twitterImage, relativeTo: base)?.absoluteURL {
            return url
        }
    }

    return nil
}

// Small regex helper used above
private func firstMatch(in text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          match.numberOfRanges >= 2,
          let r = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return String(text[r])
}

// MARK: - Date format helpers

extension DateFormatter {
    // RSS often uses RFC822/RFC1123-ish dates; we’ll try a few common formats.
    static let vr_rfc822: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)

        // We’ll attempt multiple formats by overriding dateFormat and trying again.
        return df
    }()

    // A helper to parse common RSS/Atom date strings.
    // Usage: DateFormatter.vr_rfc822.dateFromCommonRSS("Mon, 02 Jan 2006 15:04:05 GMT")
    func dateFromCommonRSS(_ string: String) -> Date? {
        let candidates = [
            "EEE, dd MMM yyyy HH:mm:ss zzz", // Mon, 02 Jan 2006 15:04:05 GMT
            "EEE, dd MMM yyyy HH:mm zzz",    // Mon, 02 Jan 2006 15:04 GMT
            "dd MMM yyyy HH:mm:ss zzz",      // 02 Jan 2006 15:04:05 GMT
            "yyyy-MM-dd'T'HH:mm:ssZ",        // 2006-01-02T15:04:05Z0700
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ"     // 2006-01-02T15:04:05.000Z
        ]
        for f in candidates {
            dateFormat = f
            if let d = date(from: string) { return d }
        }
        return nil
    }
}

