//
// ArticleSummarizer.swift
// Extracted from VibeRSS.swift
//
// This file contains the summarization engine for articles,
// including the `ArticleSummarizer` actor and its helpers.
// It is responsible for fetching HTML, extracting readable text,
// and streaming AI-based summaries (when FoundationModels is available).
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

private func regexReplace(_ string: String, pattern: String, template: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return string }
    let ns = string as NSString
    let range = NSRange(location: 0, length: ns.length)
    return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: template)
}

// MARK: - InlineSummary model for streaming summaries
#if canImport(FoundationModels)
@Generable(description: "A concise inline summary for streaming")
struct InlineSummary {
    @Guide(description: "The concise summary text")
    var text: String
}
#endif

// MARK: - ArticleSummarizer
actor ArticleSummarizer {
    static let shared = ArticleSummarizer()

    enum Length {
        case quick
        case short, long
    }

    private var cache: [String: String] = [:] // key: "<url>#<length>"
    private let cacheStoreKey = "viberss.summaryCache"
    private let expandedStoreKey = "viberss.summaryExpanded"
    private var expandedState: Set<String> = [] // keys: "<url>#<length>"

    private var saveCacheDebounceTask: Task<Void, Never>? = nil
    private var saveExpandedDebounceTask: Task<Void, Never>? = nil

    // Nonisolated hint to quickly know if a cached summary likely exists (read-only from UserDefaults)
    nonisolated static func hasCachedSummary(url: URL, length: Length) -> Bool {
        let len: String
        switch length {
        case .quick: len = "quick"
        case .short: len = "short"
        case .long:  len = "long"
        }
        let key = url.absoluteString + "#" + len
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
        let len: String
        switch length {
        case .quick: len = "quick"
        case .short: len = "short"
        case .long:  len = "long"
        }
        return url.absoluteString + "#" + len
    }

    // Helper: choose structure-aware slice for more faithful summaries
    private func selectStructureAwareSlice(from text: String, targetChars: Int) -> String {
        guard !text.isEmpty, targetChars > 0 else { return "" }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let normalizedBreaks = regexReplace(normalized, pattern: "\\n{2,}", template: "\\n\\n")

        let rawParas = normalizedBreaks.components(separatedBy: "\n\n")
        let paragraphs: [String] = rawParas
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { p in
                let lower = p.lowercased()
                if lower.contains("related posts") || lower.contains("read more") || lower.contains("subscribe") || lower.contains("newsletter") || lower.contains("sponsored") || lower.contains("advertisement") {
                    return false
                }
                let count = p.count
                if count < 30 { return false }
                if count > 1200 { return false }
                return true
            }
        let paragraphsCapped = Array(paragraphs.prefix(60))

        if paragraphsCapped.isEmpty { return String(text.prefix(targetChars)) }

        func isHeading(_ s: String) -> Bool {
            let trimmed = s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            if trimmed.count <= 80 && trimmed.last == ":" { return true }
            let words = trimmed.split(separator: " ")
            let capCount = words.filter { w in
                guard let f = w.first else { return false }
                return String(f).uppercased() == String(f) && w.count > 2
            }.count
            if words.count > 0 && capCount * 2 >= words.count { return true }
            let letters = trimmed.filter { $0.isLetter }
            if !letters.isEmpty {
                let upper = letters.filter { String($0) == String($0).uppercased() }
                if letters.count <= 80 && upper.count * 3 >= letters.count * 2 { return true }
            }
            return false
        }

        let n = paragraphsCapped.count
        var selected = Set<Int>()
        if n >= 1 { selected.insert(0) }
        if n >= 2 { selected.insert(1) }
        if n >= 3 { selected.insert(n - 1) }
        for i in 0..<n where isHeading(paragraphsCapped[i]) {
            if i > 0 { selected.insert(i - 1) }
            selected.insert(i)
            if i + 1 < n { selected.insert(i + 1) }
        }
        func currentLength(_ indices: Set<Int>) -> Int {
            indices.sorted().map { paragraphsCapped[$0] }.reduce(0) { $0 + $1.count + 2 }
        }
        var lengthNow = currentLength(selected)
        if lengthNow >= targetChars {
            let ordered = selected.sorted().map { paragraphsCapped[$0] }
            let joined = ordered.joined(separator: "\n\n")
            return joined.count <= targetChars ? joined : String(joined.prefix(targetChars))
        }
        var candidates: [Int] = []
        if n > 4 {
            let start = 2, end = n - 2
            if start < end {
                let span = end - start
                let step = max(1, span / 8)
                var i = start
                while i < end {
                    if !selected.contains(i) { candidates.append(i) }
                    i += step
                }
            }
        }
        if candidates.isEmpty {
            for i in 0..<n where !selected.contains(i) { candidates.append(i) }
        }
        for idx in candidates {
            if lengthNow >= targetChars { break }
            selected.insert(idx)
            lengthNow = currentLength(selected)
        }
        let ordered = selected.sorted().map { paragraphsCapped[$0] }
        let joined = ordered.joined(separator: "\n\n")
        return joined.count <= targetChars ? joined : String(joined.prefix(targetChars))
    }

    // Helper: fast primer slice for quicker time-to-first-token
    private func selectPrimerSlice(from text: String, maxChars: Int) -> String {
        guard !text.isEmpty, maxChars > 0 else { return "" }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let normalizedBreaks = regexReplace(normalized, pattern: "\\n{2,}", template: "\\n\\n")
        let rawParas = normalizedBreaks.components(separatedBy: "\n\n")
        let paragraphs: [String] = rawParas
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { p in
                let c = p.count
                return c >= 30 && c <= 1200
            }
        if paragraphs.isEmpty { return String(text.prefix(maxChars)) }
        var picked: [String] = []
        var total = 0
        for p in paragraphs.prefix(3) {
            if total + p.count + (picked.isEmpty ? 0 : 2) > maxChars { break }
            picked.append(p)
            total += p.count + (picked.count > 1 ? 2 : 0)
        }
        if picked.isEmpty { return String(paragraphs.first!.prefix(maxChars)) }
        let joined = picked.joined(separator: "\n\n")
        return joined.count <= maxChars ? joined : String(joined.prefix(maxChars))
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

                switch length {
                case .quick:
                    let instructions = "Summarize the article in 20 words or fewer. Use a single sentence. Focus on the single most important point. No lists, no emojis."
                    var prompt = "Summarize this article:\n\n"
                    if let seed = seedText?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !seed.isEmpty {
                        let s = String(seed.prefix(900))
                        prompt += "Preview/context from feed:\n\(s)\n\n"
                    }
                    let primer = self.selectPrimerSlice(from: baseText, maxChars: 600)
                    let promptPrimer = prompt + primer
                    do {
                        let sessionPrimer = LanguageModelSession(instructions: instructions)
                        let streamPrimer = sessionPrimer.streamResponse(to: promptPrimer, generating: InlineSummary.self)
                        var finalTextPrimer: String = ""
                        var revealedCountPrimer: Int = 0
                        let step = 2
                        let stepDelay: UInt64 = 30_000_000 // 30 ms
                        for try await partial in streamPrimer {
                            if Task.isCancelled { continuation.finish(); return }
                            guard let t = partial.content.text, !t.isEmpty else { continue }
                            finalTextPrimer = t
                            if t.count <= revealedCountPrimer { continue }
                            var target = min(revealedCountPrimer + step, t.count)
                            while target < t.count {
                                let idx = t.index(t.startIndex, offsetBy: target)
                                let prefix = String(t[..<idx])
                                continuation.yield(prefix)
                                revealedCountPrimer = target
                                try? await Task.sleep(nanoseconds: stepDelay)
                                if Task.isCancelled { continuation.finish(); return }
                                target = min(revealedCountPrimer + step, t.count)
                            }
                            continuation.yield(t)
                            revealedCountPrimer = t.count
                        }
                        if !finalTextPrimer.isEmpty {
                            self.cache[key] = finalTextPrimer
                            self.saveCache()
                            continuation.finish()
                            return
                        }
                    } catch {
                        continuation.finish()
                        return
                    }
                case .short:
                    let instructions: String = {
                        switch length {
                        case .short:
                            return "Summarize in 1 sentence (≤60 words). Focus only on key facts, outcomes, numbers, and decisions. Omit background, adjectives, and repetition. No bullet points."
                        case .long:
                            return "Summarize for busy readers in 3–6 sentences (<200 words). Focus on key facts, context, implications. No fluff. Avoid repetition."
                        default:
                            return ""
                        }
                    }()

                    var prompt = "Summarize this article:\n\n"
                    if let seed = seedText?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !seed.isEmpty {
                        let s = String(seed.prefix(900))
                        prompt += "Preview/context from feed:\n\(s)\n\n"
                    }

                    // Stage 1: quick primer
                    let primer = self.selectPrimerSlice(from: baseText, maxChars: 1000)
                    let promptPrimer = prompt + primer
                    do {
                        let sessionPrimer = LanguageModelSession(instructions: instructions)
                        let streamPrimer = sessionPrimer.streamResponse(to: promptPrimer, generating: InlineSummary.self)
                        var finalTextPrimer: String = ""
                        var revealedCountPrimer: Int = 0
                        let step = 2
                        let stepDelay: UInt64 = 30_000_000 // 30 ms
                        for try await partial in streamPrimer {
                            if Task.isCancelled { continuation.finish(); return }
                            guard let t = partial.content.text, !t.isEmpty else { continue }
                            finalTextPrimer = t
                            if t.count <= revealedCountPrimer { continue }
                            var target = min(revealedCountPrimer + step, t.count)
                            while target < t.count {
                                let idx = t.index(t.startIndex, offsetBy: target)
                                let prefix = String(t[..<idx])
                                continuation.yield(prefix)
                                revealedCountPrimer = target
                                try? await Task.sleep(nanoseconds: stepDelay)
                                if Task.isCancelled { continuation.finish(); return }
                                target = min(revealedCountPrimer + step, t.count)
                            }
                            continuation.yield(t)
                            revealedCountPrimer = t.count
                        }
                        if !finalTextPrimer.isEmpty {
                            self.cache[key] = finalTextPrimer
                            self.saveCache()
                            if finalTextPrimer.count >= 120 {
                                continuation.finish()
                                return
                            }
                        }
                    } catch {
                        // fall through
                    }

                    // Stage 2: fuller body
                    let selected = self.selectStructureAwareSlice(from: baseText, targetChars: 6000)
                    let fullBody = String(selected.prefix(6000))
                    let sessionFull = LanguageModelSession(instructions: instructions)
                    let streamFull = sessionFull.streamResponse(to: prompt + fullBody, generating: InlineSummary.self)
                    var finalTextFull: String = ""
                    var revealedCountFull: Int = 0
                    let step = 2
                    let stepDelay: UInt64 = 30_000_000 // 30 ms
                    for try await partial in streamFull {
                        if Task.isCancelled { continuation.finish(); return }
                        guard let t = partial.content.text, !t.isEmpty else { continue }
                        finalTextFull = t
                        if t.count <= revealedCountFull { continue }
                        var target = min(revealedCountFull + step, t.count)
                        while target < t.count {
                            let idx = t.index(t.startIndex, offsetBy: target)
                            let prefix = String(t[..<idx])
                            continuation.yield(prefix)
                            revealedCountFull = target
                            try? await Task.sleep(nanoseconds: stepDelay)
                            if Task.isCancelled { continuation.finish(); return }
                            target = min(revealedCountFull + step, t.count)
                        }
                        continuation.yield(t)
                        revealedCountFull = t.count
                    }
                    if !finalTextFull.isEmpty {
                        self.cache[key] = finalTextFull
                        self.saveCache()
                    }
                    continuation.finish()
                    return
                case .long:
                    let instructions = """
Summarize for busy readers in 3–6 sentences (<200 words).
Focus on key facts, context, implications, and preserve numerical details.
Preserve qualifiers (e.g., “may”, “could”, “report suggests”) and avoid overstating certainty.
Do not introduce any information that isn’t present in the text.
Avoid repetition and adjectives.
"""

                    var promptBase = "Summarize this article:\n\n"
                    if let seed = seedText?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !seed.isEmpty {
                        let s = String(seed.prefix(900))
                        promptBase += "Preview/context from feed:\n\(s)\n\n"
                    }

                    // Stage 1: primer
                    let primer = self.selectPrimerSlice(from: baseText, maxChars: 1400)
                    let promptPrimer = promptBase + primer
                    do {
                        let sessionPrimer = LanguageModelSession(instructions: instructions)
                        let streamPrimer = sessionPrimer.streamResponse(to: promptPrimer, generating: InlineSummary.self)
                        var finalTextPrimer: String = ""
                        var revealedCountPrimer: Int = 0
                        let step = 2
                        let stepDelay: UInt64 = 30_000_000 // 30 ms
                        for try await partial in streamPrimer {
                            if Task.isCancelled { continuation.finish(); return }
                            guard let t = partial.content.text, !t.isEmpty else { continue }
                            finalTextPrimer = t
                            if t.count <= revealedCountPrimer { continue }
                            var target = min(revealedCountPrimer + step, t.count)
                            while target < t.count {
                                let idx = t.index(t.startIndex, offsetBy: target)
                                let prefix = String(t[..<idx])
                                continuation.yield(prefix)
                                revealedCountPrimer = target
                                try? await Task.sleep(nanoseconds: stepDelay)
                                if Task.isCancelled { continuation.finish(); return }
                                target = min(revealedCountPrimer + step, t.count)
                            }
                            continuation.yield(t)
                            revealedCountPrimer = t.count
                        }
                        if !finalTextPrimer.isEmpty {
                            self.cache[key] = finalTextPrimer
                            self.saveCache()
                            if finalTextPrimer.count >= 160 {
                                continuation.finish()
                                return
                            }
                        }
                    } catch {
                        // continue to full pass
                    }

                    // Stage 2: full body
                    let selected = self.selectStructureAwareSlice(from: baseText, targetChars: 12_000)
                    let body = String(selected.prefix(12_000))
                    let promptFull = promptBase + body

                    do {
                        let sessionFull = LanguageModelSession(instructions: instructions)
                        let streamFull = sessionFull.streamResponse(to: promptFull, generating: InlineSummary.self)
                        var finalTextFull: String = ""
                        var revealedCountFull: Int = 0
                        let step = 2
                        let stepDelay: UInt64 = 30_000_000 // 30 ms

                        for try await partial in streamFull {
                            if Task.isCancelled { continuation.finish(); return }
                            guard let t = partial.content.text, !t.isEmpty else { continue }
                            finalTextFull = t

                            if t.count <= revealedCountFull { continue }
                            var target = min(revealedCountFull + step, t.count)
                            while target < t.count {
                                let idx = t.index(t.startIndex, offsetBy: target)
                                let prefix = String(t[..<idx])
                                continuation.yield(prefix)
                                revealedCountFull = target
                                try? await Task.sleep(nanoseconds: stepDelay)
                                if Task.isCancelled { continuation.finish(); return }
                                target = min(revealedCountFull + step, t.count)
                            }

                            continuation.yield(t)
                            revealedCountFull = t.count
                        }

                        if !finalTextFull.isEmpty {
                            self.cache[key] = finalTextFull
                            self.saveCache()
                        }
                        continuation.finish()
                        return
                    } catch {
                        continuation.finish()
                        return
                    }
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
        var s = String(html.prefix(200_000))
        if Task.isCancelled { return "" }
        s = regexReplace(s, pattern: "<!--[\\s\\S]*?-->", template: " ")

        if let articleRegex = try? NSRegularExpression(pattern: "<article[\\n\\r\\s\\S]*?</article>", options: []) {
            let ns = s as NSString
            let fullRange = NSRange(location: 0, length: ns.length)
            if let match = articleRegex.firstMatch(in: s, options: [], range: fullRange) {
                let r = Range(match.range, in: s)!
                s = String(s[r])
            }
        }
        if Task.isCancelled { return "" }

        let blocks = ["nav", "header", "footer", "aside"]
        for tag in blocks {
            if let regex = try? NSRegularExpression(pattern: "<" + tag + "[\\n\\r\\s\\S]*?</" + tag + ">", options: [.caseInsensitive]) {
                s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
            }
        }

        if let regex = try? NSRegularExpression(pattern: "<script[\\n\\r\\s\\S]*?</script>", options: [.caseInsensitive]) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
        }
        if Task.isCancelled { return "" }
        if let regex = try? NSRegularExpression(pattern: "<style[\\n\\r\\s\\S]*?</style>", options: [.caseInsensitive]) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
        }

        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
        }
        if Task.isCancelled { return "" }

        let attr = try? AttributedString(markdown: s)
        let plain = attr?.description ?? s

        let collapsed = regexReplace(plain, pattern: "\\s+", template: " ")
        if Task.isCancelled { return "" }
        return collapsed.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
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

