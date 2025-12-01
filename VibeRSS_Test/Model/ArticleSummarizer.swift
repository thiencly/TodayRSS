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

    // In-memory set for fast O(1) lookup of cached keys (avoids JSON decode on every check)
    private static var cachedKeysLookup: Set<String> = []
    private static var lookupInitialized = false
    private static let lookupLock = NSLock()

    // Initialize lookup from UserDefaults - call this once at app startup on background thread
    static func initializeLookupAsync() {
        DispatchQueue.global(qos: .userInitiated).async {
            lookupLock.lock()
            defer { lookupLock.unlock() }
            guard !lookupInitialized else { return }

            if let data = UserDefaults.standard.data(forKey: "viberss.summaryCache"),
               let dict = try? JSONDecoder().decode([String: String].self, from: data) {
                cachedKeysLookup = Set(dict.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.keys)
            }
            lookupInitialized = true
        }
    }

    // Update the lookup when cache changes
    private static func addToLookup(_ key: String) {
        lookupLock.lock()
        cachedKeysLookup.insert(key)
        lookupLock.unlock()
    }

    private static func removeFromLookup(_ key: String) {
        lookupLock.lock()
        cachedKeysLookup.remove(key)
        lookupLock.unlock()
    }

    static func clearLookup() {
        lookupLock.lock()
        cachedKeysLookup.removeAll()
        lookupLock.unlock()
    }

    // Fast O(1) check - no JSON decoding
    nonisolated static func hasCachedSummary(url: URL, length: Length) -> Bool {
        let len: String
        switch length {
        case .quick: len = "quick"
        case .short: len = "short"
        case .long:  len = "long"
        }
        let key = url.absoluteString + "#" + len
        lookupLock.lock()
        let result = cachedKeysLookup.contains(key)
        lookupLock.unlock()
        return result
    }

    private var isWarmedUp = false

    init() {
        cache = Self.loadCacheFromDefaults()
        expandedState = Self.loadExpandedFromDefaults()
    }

    #if canImport(FoundationModels)
    private var heroSession: LanguageModelSession?
    private var summarySessionShort: LanguageModelSession?
    private var summarySessionLong: LanguageModelSession?
    #endif

    /// Call this early in app launch to pre-load the on-device model
    func warmUp() async {
        guard !isWarmedUp else { return }
        isWarmedUp = true

        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return }

        // Create and cache a session for hero card summaries
        let session = LanguageModelSession(instructions: "Summarize in one sentence, 20 words max.")
        heroSession = session

        // Pre-create summary sessions for faster first summarization
        let shortInstructions = "Summarize in 1 sentence (≤60 words). Focus only on key facts, outcomes, numbers, and decisions. Omit background, adjectives, and repetition. No bullet points."
        let longInstructions = "Summarize for busy readers in 3–6 sentences (<200 words). Focus on key facts, context, implications. Preserve qualifiers and numerical details. No fluff."
        summarySessionShort = LanguageModelSession(instructions: shortInstructions)
        summarySessionLong = LanguageModelSession(instructions: longInstructions)

        // Run a tiny prompt to trigger model loading
        do {
            _ = try await session.respond(to: "Hi", generating: InlineSummary.self)
        } catch {
            // Warm-up failed, but that's okay - model will load on first real request
        }
        #endif
    }

    /// Fast summary for hero cards - optimized for speed
    func fastHeroSummary(url: URL, articleText: String?) async -> String? {
        let key = makeCacheKey(url: url, length: .quick)
        if let cached = cache[key], !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cached
        } else if cache[key] != nil {
            // Remove invalid empty cache entry
            cache.removeValue(forKey: key)
            Self.removeFromLookup(key)
        }

        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }

        // Get article text
        let baseText: String
        if let text = articleText, !text.isEmpty {
            baseText = text
        } else if let cachedText = await ArticleTextCache.shared.cachedText(for: url), !cachedText.isEmpty {
            baseText = cachedText
        } else {
            guard let html = try? await fetchHTML(url: url) else { return nil }
            let extracted = extractReadableText(from: String(html.prefix(100_000)))
            if extracted.isEmpty { return nil }
            baseText = extracted
            await ArticleTextCache.shared.storeText(extracted, for: url)
        }

        // Use smaller primer for faster processing
        let primer = selectPrimerSlice(from: baseText, maxChars: 300)
        if primer.isEmpty { return nil }

        do {
            // Reuse cached session or create new one
            let session = heroSession ?? LanguageModelSession(instructions: "Summarize in one sentence, 20 words max.")
            if heroSession == nil { heroSession = session }

            // Use respond() instead of streamResponse() - no streaming delays
            let result = try await session.respond(to: primer, generating: InlineSummary.self)
            let text = result.content.text
            if !text.isEmpty {
                cache[key] = text
                Self.addToLookup(key)
                saveCache()
                return text
            }
        } catch {
            // Fall through
        }
        #endif

        return nil
    }

    private static func loadCacheFromDefaults() -> [String: String] {
        if let data = UserDefaults.standard.data(forKey: "viberss.summaryCache"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            // Filter out any empty entries that may have been saved previously
            return dict.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
        // Filter out empty entries before saving
        let validCache = cache.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let data = try? JSONEncoder().encode(validCache) else { return }
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
        Self.clearLookup()
        UserDefaults.standard.removeObject(forKey: cacheStoreKey)
        UserDefaults.standard.removeObject(forKey: expandedStoreKey)
    }

    /// Clears only article summaries (short/long) used by the Summarize button, not hero summaries
    func clearArticleSummaries() {
        let keysToRemove = cache.keys.filter { $0.hasSuffix("#short") || $0.hasSuffix("#long") }
        for key in keysToRemove {
            cache.removeValue(forKey: key)
            Self.removeFromLookup(key)
        }
        expandedState.removeAll()
        saveCache()
        saveExpanded()
    }

    /// Clears only hero summaries (quick) used by the hero card
    func clearHeroSummaries() {
        let keysToRemove = cache.keys.filter { $0.hasSuffix("#quick") }
        for key in keysToRemove {
            cache.removeValue(forKey: key)
            Self.removeFromLookup(key)
        }
        saveCache()
    }

    func cachedSummary(for url: URL, length: Length) -> String? {
        let key = makeCacheKey(url: url, length: length)
        if let cached = cache[key], !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cached
        }
        // Remove invalid empty cache entry if present
        if cache[key] != nil {
            cache.removeValue(forKey: key)
            Self.removeFromLookup(key)
        }
        return nil
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
                if let cached = cache[key], !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.yield(cached)
                    continuation.finish()
                    return
                } else if cache[key] != nil {
                    // Remove invalid empty cache entry
                    cache.removeValue(forKey: key)
                    Self.removeFromLookup(key)
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
                    baseText = String(cachedText.prefix(150_000))
                } else {
                    guard let html = try? await fetchHTML(url: url) else {
                        continuation.finish()
                        return
                    }
                    let limitedHTML = String(html.prefix(150_000))
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
                        let stepDelay: UInt64 = 20_000_000 // 20 ms (faster typewriter)
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
                            Self.addToLookup(key)
                            self.saveCache()
                            continuation.finish()
                            return
                        }
                    } catch {
                        continuation.finish()
                        return
                    }
                case .short:
                    let instructions = "Summarize in 1 sentence (≤60 words). Focus only on key facts, outcomes, numbers, and decisions. Omit background, adjectives, and repetition. No bullet points."

                    var prompt = "Summarize this article:\n\n"
                    if let seed = seedText?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !seed.isEmpty {
                        let s = String(seed.prefix(900))
                        prompt += "Preview/context from feed:\n\(s)\n\n"
                    }

                    // Reuse cached session or create new one
                    let session = self.summarySessionShort ?? LanguageModelSession(instructions: instructions)
                    if self.summarySessionShort == nil { self.summarySessionShort = session }

                    // Stage 1: quick primer
                    let primer = self.selectPrimerSlice(from: baseText, maxChars: 1000)
                    let promptPrimer = prompt + primer
                    do {
                        let streamPrimer = session.streamResponse(to: promptPrimer, generating: InlineSummary.self)
                        var finalTextPrimer: String = ""
                        var revealedCountPrimer: Int = 0
                        let step = 2
                        let stepDelay: UInt64 = 20_000_000 // 20 ms (faster typewriter)
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
                            Self.addToLookup(key)
                            self.saveCache()
                            // Skip Stage 2 if primer covers enough content or result is sufficient
                            if finalTextPrimer.count >= 100 || primer.count >= baseText.count / 2 {
                                continuation.finish()
                                return
                            }
                        }
                    } catch {
                        // fall through to Stage 2
                    }

                    // Stage 2: fuller body (reuse same session)
                    let selected = self.selectStructureAwareSlice(from: baseText, targetChars: 6000)
                    let fullBody = String(selected.prefix(6000))
                    let streamFull = session.streamResponse(to: prompt + fullBody, generating: InlineSummary.self)
                    var finalTextFull: String = ""
                    var revealedCountFull: Int = 0
                    let step = 2
                    let stepDelay: UInt64 = 20_000_000 // 20 ms (faster typewriter)
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
                        Self.addToLookup(key)
                        self.saveCache()
                    }
                    continuation.finish()
                    return
                case .long:
                    let instructions = """
Summarize for busy readers in 3–6 sentences (<200 words).
Focus on key facts, context, implications, and preserve numerical details.
Preserve qualifiers (e.g., "may", "could", "report suggests") and avoid overstating certainty.
Do not introduce any information that isn't present in the text.
Avoid repetition and adjectives.
"""

                    var promptBase = "Summarize this article:\n\n"
                    if let seed = seedText?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !seed.isEmpty {
                        let s = String(seed.prefix(900))
                        promptBase += "Preview/context from feed:\n\(s)\n\n"
                    }

                    // Reuse cached session or create new one
                    let session = self.summarySessionLong ?? LanguageModelSession(instructions: instructions)
                    if self.summarySessionLong == nil { self.summarySessionLong = session }

                    // Stage 1: primer
                    let primer = self.selectPrimerSlice(from: baseText, maxChars: 1400)
                    let promptPrimer = promptBase + primer
                    do {
                        let streamPrimer = session.streamResponse(to: promptPrimer, generating: InlineSummary.self)
                        var finalTextPrimer: String = ""
                        var revealedCountPrimer: Int = 0
                        let step = 2
                        let stepDelay: UInt64 = 20_000_000 // 20 ms (faster typewriter)
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
                            Self.addToLookup(key)
                            self.saveCache()
                            // Skip Stage 2 if primer covers enough content or result is sufficient
                            if finalTextPrimer.count >= 140 || primer.count >= baseText.count / 2 {
                                continuation.finish()
                                return
                            }
                        }
                    } catch {
                        // continue to full pass
                    }

                    // Stage 2: full body (reuse same session)
                    let selected = self.selectStructureAwareSlice(from: baseText, targetChars: 12_000)
                    let body = String(selected.prefix(12_000))
                    let promptFull = promptBase + body

                    let streamFull = session.streamResponse(to: promptFull, generating: InlineSummary.self)
                    var finalTextFull: String = ""
                    var revealedCountFull: Int = 0
                    let step = 2
                    let stepDelay: UInt64 = 20_000_000 // 20 ms (faster typewriter)

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
                        Self.addToLookup(key)
                        self.saveCache()
                    }
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

