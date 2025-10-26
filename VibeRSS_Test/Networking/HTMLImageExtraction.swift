// FILE: Utilities/HTMLImageExtraction.swift
// PURPOSE: Helper to extract the first <img src=...> URL from HTML content
// SAFE TO EDIT: Yes, but regex must remain valid

import Foundation

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
