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

// MARK: - Cached Regex Patterns
private enum CachedRegex {
    // Pre-compiled regex patterns for performance (compiled once, reused forever)
    static let multipleNewlines = try! NSRegularExpression(pattern: "\\n{2,}", options: [])
    static let whitespace = try! NSRegularExpression(pattern: "\\s+", options: [])
    static let htmlComments = try! NSRegularExpression(pattern: "<!--[\\s\\S]*?-->", options: [])
    static let articleTag = try! NSRegularExpression(pattern: "<article[\\n\\r\\s\\S]*?</article>", options: [])
    static let scriptTag = try! NSRegularExpression(pattern: "<script[\\n\\r\\s\\S]*?</script>", options: [.caseInsensitive])
    static let styleTag = try! NSRegularExpression(pattern: "<style[\\n\\r\\s\\S]*?</style>", options: [.caseInsensitive])
    static let anyHtmlTag = try! NSRegularExpression(pattern: "<[^>]+>", options: [])
    static let navTag = try! NSRegularExpression(pattern: "<nav[\\n\\r\\s\\S]*?</nav>", options: [.caseInsensitive])
    static let headerTag = try! NSRegularExpression(pattern: "<header[\\n\\r\\s\\S]*?</header>", options: [.caseInsensitive])
    static let footerTag = try! NSRegularExpression(pattern: "<footer[\\n\\r\\s\\S]*?</footer>", options: [.caseInsensitive])
    static let asideTag = try! NSRegularExpression(pattern: "<aside[\\n\\r\\s\\S]*?</aside>", options: [.caseInsensitive])

    // Cache for dynamic patterns (rarely used)
    private static var dynamicCache: [String: NSRegularExpression] = [:]
    private static let cacheLock = NSLock()

    static func get(pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        let key = "\(pattern)_\(options.rawValue)"
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = dynamicCache[key] {
            return cached
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        dynamicCache[key] = regex
        return regex
    }
}

private func regexReplace(_ string: String, pattern: String, template: String) -> String {
    guard let regex = CachedRegex.get(pattern: pattern) else { return string }
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

// MARK: - Apple Intelligence Availability

/// Check if Apple Intelligence (on-device AI) is available on this device
/// Returns true on iPhone 16+, iPad with M-series chip, running iOS 26+
enum AppleIntelligence {
    /// Check availability - can be called from any thread
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        if case .available = model.availability {
            return true
        }
        #endif
        return false
    }
}

// MARK: - ArticleSummarizer
actor ArticleSummarizer {
    static let shared = ArticleSummarizer()

    enum Length {
        case quick
        case reel       // ~50 words, between quick (25) and short (80)
        case reelExpanded  // ~100-120 words, for news reel expanded view
        case short
        case detailed   // ~200-250 words, comprehensive summary for reader mode
    }

    private var cache: [String: String] = [:] // key: "<url>#<length>"
    private let cacheStoreKey = "viberss.summaryCache"
    private let expandedStoreKey = "viberss.summaryExpanded"
    private let maxCacheEntries = 1000 // Keep last ~333 articles (3 lengths each)
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
            // Check without lock first (fast path)
            if lookupInitialized { return }

            // Do JSON decoding OUTSIDE the lock to avoid blocking main thread
            var keys: Set<String> = []
            if let data = UserDefaults.standard.data(forKey: "viberss.summaryCache"),
               let dict = try? JSONDecoder().decode([String: String].self, from: data) {
                keys = Set(dict.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.keys)
            }

            // Only hold lock briefly to update state
            lookupLock.lock()
            defer { lookupLock.unlock() }
            guard !lookupInitialized else { return }
            cachedKeysLookup = keys
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
        case .reel:  len = "reel"
        case .reelExpanded: len = "reelExpanded"
        case .short: len = "short"
        case .detailed: len = "detailed"
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
        // Prune on load if over limit
        if cache.count > maxCacheEntries {
            pruneCacheIfNeeded()
        }
    }

    /// Removes oldest entries to stay under maxCacheEntries limit
    private func pruneCacheIfNeeded() {
        guard cache.count > maxCacheEntries else { return }
        let keysToRemove = Array(cache.keys.prefix(cache.count - maxCacheEntries))
        for key in keysToRemove {
            cache.removeValue(forKey: key)
            Self.removeFromLookup(key)
        }
        saveCache()
    }

    #if canImport(FoundationModels)
    private var heroSession: LanguageModelSession?
    private var reelSession: LanguageModelSession?
    private var reelExpandedSession: LanguageModelSession?
    private var summarySessionShort: LanguageModelSession?
    private var summarySessionDetailed: LanguageModelSession?

    // Session pool for concurrent requests (hero cards load 4 articles in parallel)
    private var heroSessionPool: [LanguageModelSession] = []
    private var reelSessionPool: [LanguageModelSession] = []
    private let poolSize = 4 // Matches typical concurrent hero card requests

    /// Get a session from the pool, or create a new one if pool is empty
    private func getHeroSession() -> LanguageModelSession {
        if let session = heroSessionPool.popLast() {
            return session
        }
        // Pool empty, create new session
        return LanguageModelSession(instructions: "Summarize in 1-2 sentences, about 25 words. Focus on the key point and one important detail.")
    }

    /// Return a session to the pool (if pool isn't full)
    private func returnHeroSession(_ session: LanguageModelSession) {
        if heroSessionPool.count < poolSize {
            heroSessionPool.append(session)
        }
        // If pool is full, session is discarded (will be garbage collected)
    }

    /// Get a reel session from the pool
    private func getReelSession() -> LanguageModelSession {
        if let session = reelSessionPool.popLast() {
            return session
        }
        return LanguageModelSession(instructions: "Summarize in 2-3 sentences, about 50-60 words. Cover the main point and key facts. Make it engaging and informative. No lists, no emojis.")
    }

    /// Return a reel session to the pool
    private func returnReelSession(_ session: LanguageModelSession) {
        if reelSessionPool.count < poolSize {
            reelSessionPool.append(session)
        }
    }

    /// Reset all cached sessions - call when sessions become stale
    private func resetSessions() {
        heroSession = nil
        reelSession = nil
        reelExpandedSession = nil
        summarySessionShort = nil
        summarySessionDetailed = nil
        heroSessionPool.removeAll()
        reelSessionPool.removeAll()
    }

    /// Re-warm a specific session type in the background after reset
    private func rewarmSession(_ type: Length) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return }

            switch type {
            case .quick:
                let session = LanguageModelSession(instructions: "Summarize in 1-2 sentences, about 25 words. Focus on the key point and one important detail.")
                await self.setHeroSession(session)
            case .reel:
                let session = LanguageModelSession(instructions: "Summarize in 2-3 sentences, about 50-60 words. Cover the main point and key facts. Make it engaging and informative. No lists, no emojis.")
                await self.setReelSession(session)
            case .reelExpanded:
                let session = LanguageModelSession(instructions: "Summarize in 4-5 sentences (100-120 words). Cover the main point, key facts, and important context. Make it informative and complete. No lists, no emojis.")
                await self.setReelExpandedSession(session)
            case .short:
                let session = LanguageModelSession(instructions: "Summarize in 2-3 sentences (60-80 words). Cover the main point and key facts. Make it concise and informative. No lists, no emojis.")
                await self.setShortSession(session)
            case .detailed:
                let session = LanguageModelSession(instructions: "Provide a comprehensive summary in 6-8 sentences (200-250 words). Cover the main thesis, key arguments, important facts, and conclusions. Be thorough but avoid repetition. No lists, no emojis.")
                await self.setDetailedSession(session)
            }
        }
    }

    private func setHeroSession(_ session: LanguageModelSession) {
        if heroSession == nil { heroSession = session }
    }

    private func setReelSession(_ session: LanguageModelSession) {
        if reelSession == nil { reelSession = session }
    }

    private func setReelExpandedSession(_ session: LanguageModelSession) {
        if reelExpandedSession == nil { reelExpandedSession = session }
    }

    private func setShortSession(_ session: LanguageModelSession) {
        if summarySessionShort == nil { summarySessionShort = session }
    }

    private func setDetailedSession(_ session: LanguageModelSession) {
        if summarySessionDetailed == nil { summarySessionDetailed = session }
    }
    #endif

    /// Call this early in app launch to pre-load the on-device model
    func warmUp() async {
        guard !isWarmedUp else { return }
        isWarmedUp = true

        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return }

        // Pre-populate hero session pool for concurrent requests
        let heroInstructions = "Summarize in 1-2 sentences, about 25 words. Focus on the key point and one important detail."
        for _ in 0..<poolSize {
            heroSessionPool.append(LanguageModelSession(instructions: heroInstructions))
        }

        // Pre-populate reel session pool
        let reelInstructions = "Summarize in 2-3 sentences, about 50-60 words. Cover the main point and key facts. Make it engaging and informative. No lists, no emojis."
        for _ in 0..<poolSize {
            reelSessionPool.append(LanguageModelSession(instructions: reelInstructions))
        }

        // Keep single sessions for streaming summaries (not concurrent)
        heroSession = heroSessionPool.first
        reelSession = reelSessionPool.first

        // Pre-create reel expanded session for expanded news reel view (~100-120 words)
        let reelExpandedInstructions = "Summarize in 4-5 sentences (100-120 words). Cover the main point, key facts, and important context. Make it informative and complete. No lists, no emojis."
        reelExpandedSession = LanguageModelSession(instructions: reelExpandedInstructions)

        // Pre-create summary session for faster first summarization
        let shortInstructions = "Summarize in 2-3 sentences (60-80 words). Cover the main point and key facts. Make it concise and informative. No lists, no emojis."
        summarySessionShort = LanguageModelSession(instructions: shortInstructions)

        // Run a tiny prompt to trigger model loading (use first pooled session)
        if let session = heroSessionPool.first {
            do {
                _ = try await session.respond(to: "Hi", generating: InlineSummary.self)
            } catch {
                // Warm-up failed, but that's okay - model will load on first real request
            }
        }
        #endif
    }

    /// Minimum character count for RSS description to be considered substantial enough for summarization
    private let minDescriptionLength = 200

    /// Maximum word count for hero summaries (truncate if AI exceeds this)
    private let maxHeroWords = 28

    /// Truncate text to a maximum word count, ending at a sentence boundary if possible
    nonisolated private func truncateToWordLimit(_ text: String, maxWords: Int) -> String {
        let words = text.split(separator: " ")
        guard words.count > maxWords else { return text }

        // Take maxWords and join them
        let truncated = words.prefix(maxWords).joined(separator: " ")

        // Try to end at a sentence boundary (. ! ?)
        if let lastSentenceEnd = truncated.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
            let endIndex = truncated.index(after: lastSentenceEnd)
            let atSentence = String(truncated[..<endIndex])
            // Only use sentence boundary if we keep at least 60% of the words
            if atSentence.split(separator: " ").count >= maxWords * 6 / 10 {
                return atSentence
            }
        }

        // No good sentence boundary, just truncate and add ellipsis
        return truncated + "…"
    }

    /// Clean HTML tags from RSS description text
    nonisolated private func cleanDescription(_ text: String) -> String {
        var cleaned = text
        // Remove HTML tags
        let range = NSRange(location: 0, length: (cleaned as NSString).length)
        cleaned = CachedRegex.anyHtmlTag.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: " ")
        // Collapse whitespace
        let cleanedRange = NSRange(location: 0, length: (cleaned as NSString).length)
        cleaned = CachedRegex.whitespace.stringByReplacingMatches(in: cleaned, options: [], range: cleanedRange, withTemplate: " ")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fast summary for hero cards - optimized for speed
    /// - Parameters:
    ///   - url: Article URL
    ///   - fallbackText: RSS description to use (preferred if substantial, fallback otherwise)
    func fastHeroSummary(url: URL, articleText fallbackText: String?) async -> String? {
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

        // Clean the RSS description first
        let cleanedDescription = fallbackText.map { cleanDescription($0) }
        let minDescriptionLength = 400

        // Priority: 1) Cached full article text (from background sync)
        //           2) RSS description if 400+ chars
        //           3) Fetch HTML and extract text
        let baseText: String
        if let cachedText = await ArticleTextCache.shared.cachedText(for: url), !cachedText.isEmpty {
            // Best: use cached full article text from background sync
            baseText = cachedText
        } else if let description = cleanedDescription, description.count >= minDescriptionLength {
            // Good: use RSS description if it's long enough (400+ chars)
            baseText = description
        } else {
            // Fallback: fetch HTML and extract text
            do {
                let html = try await fetchHTML(url: url)
                let extracted = extractReadableText(from: String(html.prefix(100_000)))
                if !extracted.isEmpty {
                    baseText = extracted
                } else if let description = cleanedDescription, !description.isEmpty {
                    // Use short description as last resort
                    baseText = description
                } else {
                    return nil
                }
            } catch {
                // Network error - use short description if available
                if let description = cleanedDescription, !description.isEmpty {
                    baseText = description
                } else {
                    return nil
                }
            }
        }

        // Use structure-aware slice for better content coverage
        // Reduced from 1000 to 600 chars for faster AI processing (still enough for 25-word summary)
        let primer = selectStructureAwareSlice(from: baseText, targetChars: 600)
        if primer.isEmpty { return nil }

        // Get session from pool (reuse pre-warmed sessions)
        let session = getHeroSession()

        do {
            // Use respond() instead of streamResponse() - no streaming delays
            let result = try await session.respond(to: primer, generating: InlineSummary.self)
            var text = result.content.text

            // Return session to pool for reuse
            returnHeroSession(session)

            if !text.isEmpty {
                // Enforce word limit - AI sometimes exceeds the 25 word target
                text = truncateToWordLimit(text, maxWords: maxHeroWords)

                cache[key] = text
                Self.addToLookup(key)
                saveCache()
                return text
            }
        } catch {
            // Don't return failed session to pool - it may be in bad state
            print("Hero summary error: \(error)")

            // Only show blocked message for guardrail violations, not for concurrent request errors
            let errorDesc = String(describing: error).lowercased()
            if errorDesc.contains("guardrail") || errorDesc.contains("unsafe") || errorDesc.contains("sensitive") {
                let blockedText = "Summary blocked by Apple"
                cache[key] = blockedText
                Self.addToLookup(key)
                saveCache()
                return blockedText
            }
            // For other errors (like concurrent requests), just return nil to allow retry
        }
        #endif

        return nil
    }

    /// Reel summary for news reel cards - ~50-60 words, 2-3 sentences
    /// Optimized for speed like fastHeroSummary but with slightly more detail
    func fastReelSummary(url: URL, articleText fallbackText: String?) async -> String? {
        let key = makeCacheKey(url: url, length: .reel)
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

        // Clean the RSS description first
        let cleanedDescription = fallbackText.map { cleanDescription($0) }
        let hasSubstantialDescription = (cleanedDescription?.count ?? 0) >= minDescriptionLength

        // Priority: 1) Cached full article, 2) Substantial RSS description, 3) Fetch HTML, 4) Short RSS description
        let baseText: String
        if let cachedText = await ArticleTextCache.shared.cachedText(for: url), !cachedText.isEmpty {
            baseText = cachedText
        } else if hasSubstantialDescription, let description = cleanedDescription {
            // RSS description is substantial enough - skip HTML fetch for speed
            baseText = description
        } else if let html = try? await fetchHTMLWithAdaptiveTimeout(url: url) {
            let extracted = extractReadableText(from: String(html.prefix(100_000)))
            if !extracted.isEmpty {
                baseText = extracted
                await ArticleTextCache.shared.storeText(extracted, for: url)
            } else if let description = cleanedDescription, !description.isEmpty {
                baseText = description
            } else {
                return nil
            }
        } else if let description = cleanedDescription, !description.isEmpty {
            baseText = description
        } else {
            return nil
        }

        // Use structure-aware slice for better content coverage
        let primer = selectStructureAwareSlice(from: baseText, targetChars: 2500)
        if primer.isEmpty { return nil }

        // Get session from pool (reuse pre-warmed sessions)
        let session = getReelSession()

        do {
            let result = try await session.respond(to: primer, generating: InlineSummary.self)
            let text = result.content.text

            // Return session to pool for reuse
            returnReelSession(session)

            if !text.isEmpty {
                cache[key] = text
                Self.addToLookup(key)
                saveCache()
                return text
            }
        } catch {
            // Don't return failed session to pool
            print("Reel summary error: \(error)")

            // Only show blocked message for guardrail violations
            let errorDesc = String(describing: error).lowercased()
            if errorDesc.contains("guardrail") || errorDesc.contains("unsafe") || errorDesc.contains("sensitive") {
                let blockedText = "Summary blocked by Apple"
                cache[key] = blockedText
                Self.addToLookup(key)
                saveCache()
                return blockedText
            }
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

    /// Clears all summaries of every kind (quick, reel, reelExpanded, short)
    func clearArticleSummaries() {
        cache.removeAll()
        Self.clearLookup()
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
        case .reel:  len = "reel"
        case .reelExpanded: len = "reelExpanded"
        case .short: len = "short"
        case .detailed: len = "detailed"
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

    /// Stream a summary using pre-extracted article text (for reader mode)
    func streamSummaryFromText(url: URL, articleText: String, length: Length) async -> AsyncStream<String> {
        AsyncStream { continuation in
            let worker = Task {
                let key = makeCacheKey(url: url, length: length)
                if let cached = cache[key], !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.yield(cached)
                    continuation.finish()
                    return
                } else if cache[key] != nil {
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

                let baseText = String(articleText.prefix(150_000))
                guard !baseText.isEmpty else {
                    continuation.finish()
                    return
                }

                // Only handle detailed length for reader mode
                guard length == .detailed else {
                    continuation.finish()
                    return
                }

                let instructions = "Provide a comprehensive summary in 6-8 sentences (200-250 words). Cover the main thesis, key arguments, important facts, and conclusions. Be thorough but avoid repetition. No lists, no emojis."
                let prompt = "Summarize this article comprehensively:\n\n"
                let primer = self.selectStructureAwareSlice(from: baseText, targetChars: 5000)
                let promptPrimer = prompt + primer

                do {
                    let session = self.summarySessionDetailed ?? LanguageModelSession(instructions: instructions)
                    if self.summarySessionDetailed == nil { self.summarySessionDetailed = session }

                    let streamDetailed = session.streamResponse(to: promptPrimer, generating: InlineSummary.self)
                    var finalText: String = ""
                    var revealedCount: Int = 0
                    let step = 2
                    let stepDelay: UInt64 = 20_000_000 // 20 ms
                    for try await partial in streamDetailed {
                        if Task.isCancelled { continuation.finish(); return }
                        guard let t = partial.content.text, !t.isEmpty else { continue }
                        finalText = t
                        if t.count <= revealedCount { continue }
                        var target = min(revealedCount + step, t.count)
                        while target < t.count {
                            let idx = t.index(t.startIndex, offsetBy: target)
                            let prefix = String(t[..<idx])
                            continuation.yield(prefix)
                            HapticManager.shared.typingHaptic()
                            revealedCount = target
                            try? await Task.sleep(nanoseconds: stepDelay)
                            if Task.isCancelled { continuation.finish(); return }
                            target = min(revealedCount + step, t.count)
                        }
                        continuation.yield(t)
                        HapticManager.shared.typingHaptic()
                        revealedCount = t.count
                    }
                    if !finalText.isEmpty {
                        self.cache[key] = finalText
                        Self.addToLookup(key)
                        self.saveCache()
                        HapticManager.shared.success()
                        continuation.finish()
                        return
                    } else {
                        self.summarySessionDetailed = nil
                        self.rewarmSession(.detailed)
                    }
                } catch {
                    self.summarySessionDetailed = nil
                    self.rewarmSession(.detailed)
                    print("StreamSummaryFromText detailed error: \(error)")

                    // Only show blocked message for guardrail violations
                    let errorDesc = String(describing: error).lowercased()
                    if errorDesc.contains("guardrail") || errorDesc.contains("unsafe") || errorDesc.contains("sensitive") {
                        let blockedText = "Summary blocked by Apple"
                        self.cache[key] = blockedText
                        Self.addToLookup(key)
                        self.saveCache()
                        continuation.yield(blockedText)
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
                case .quick, .reel:
                    // These use fastHeroSummary and fastReelSummary respectively (non-streaming)
                    continuation.finish()
                    return
                case .reelExpanded:
                    // Reel expanded summaries (~100-120 words) - for news reel expanded view
                    let instructions = "Summarize in 4-5 sentences (100-120 words). Cover the main point, key facts, and important context. Make it informative and complete. No lists, no emojis."
                    var prompt = "Summarize this article:\n\n"
                    if let seed = seedText?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !seed.isEmpty {
                        let s = String(seed.prefix(900))
                        prompt += "Preview/context from feed:\n\(s)\n\n"
                    }
                    // Use structure-aware slice for expanded summaries - pulls from throughout the article
                    let primer = self.selectStructureAwareSlice(from: baseText, targetChars: 3500)
                    let promptPrimer = prompt + primer
                    do {
                        let session = self.reelExpandedSession ?? LanguageModelSession(instructions: instructions)
                        if self.reelExpandedSession == nil { self.reelExpandedSession = session }

                        let streamReelExp = session.streamResponse(to: promptPrimer, generating: InlineSummary.self)
                        var finalText: String = ""
                        var revealedCount: Int = 0
                        let step = 2
                        let stepDelay: UInt64 = 20_000_000 // 20 ms
                        for try await partial in streamReelExp {
                            if Task.isCancelled { continuation.finish(); return }
                            guard let t = partial.content.text, !t.isEmpty else { continue }
                            finalText = t
                            if t.count <= revealedCount { continue }
                            var target = min(revealedCount + step, t.count)
                            while target < t.count {
                                let idx = t.index(t.startIndex, offsetBy: target)
                                let prefix = String(t[..<idx])
                                continuation.yield(prefix)
                                HapticManager.shared.typingHaptic()
                                revealedCount = target
                                try? await Task.sleep(nanoseconds: stepDelay)
                                if Task.isCancelled { continuation.finish(); return }
                                target = min(revealedCount + step, t.count)
                            }
                            continuation.yield(t)
                            HapticManager.shared.typingHaptic()
                            revealedCount = t.count
                        }
                        if !finalText.isEmpty {
                            self.cache[key] = finalText
                            Self.addToLookup(key)
                            self.saveCache()
                            HapticManager.shared.success()
                            continuation.finish()
                            return
                        } else {
                            self.reelExpandedSession = nil
                            self.rewarmSession(.reelExpanded)
                        }
                    } catch {
                        self.reelExpandedSession = nil
                        self.rewarmSession(.reelExpanded)
                        print("StreamSummary reelExpanded error: \(error)")

                        let errorDesc = String(describing: error).lowercased()
                        if errorDesc.contains("guardrail") || errorDesc.contains("unsafe") || errorDesc.contains("sensitive") {
                            let blockedText = "Summary blocked by Apple"
                            self.cache[key] = blockedText
                            Self.addToLookup(key)
                            self.saveCache()
                            continuation.yield(blockedText)
                        }
                        continuation.finish()
                        return
                    }
                case .short:
                    // Short summaries (~60-80 words) - single stage approach
                    let instructions = "Summarize in 2-3 sentences (60-80 words). Cover the main point and key facts. Make it concise and informative. No lists, no emojis."
                    var prompt = "Summarize this article:\n\n"
                    if let seed = seedText?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !seed.isEmpty {
                        let s = String(seed.prefix(900))
                        prompt += "Preview/context from feed:\n\(s)\n\n"
                    }
                    // Use structure-aware slice for better content coverage
                    let primer = self.selectStructureAwareSlice(from: baseText, targetChars: 2500)
                    let promptPrimer = prompt + primer
                    do {
                        let session = self.summarySessionShort ?? LanguageModelSession(instructions: instructions)
                        if self.summarySessionShort == nil { self.summarySessionShort = session }

                        let streamShort = session.streamResponse(to: promptPrimer, generating: InlineSummary.self)
                        var finalText: String = ""
                        var revealedCount: Int = 0
                        let step = 2
                        let stepDelay: UInt64 = 20_000_000 // 20 ms
                        for try await partial in streamShort {
                            if Task.isCancelled { continuation.finish(); return }
                            guard let t = partial.content.text, !t.isEmpty else { continue }
                            finalText = t
                            if t.count <= revealedCount { continue }
                            var target = min(revealedCount + step, t.count)
                            while target < t.count {
                                let idx = t.index(t.startIndex, offsetBy: target)
                                let prefix = String(t[..<idx])
                                continuation.yield(prefix)
                                HapticManager.shared.typingHaptic()
                                revealedCount = target
                                try? await Task.sleep(nanoseconds: stepDelay)
                                if Task.isCancelled { continuation.finish(); return }
                                target = min(revealedCount + step, t.count)
                            }
                            continuation.yield(t)
                            HapticManager.shared.typingHaptic()
                            revealedCount = t.count
                        }
                        if !finalText.isEmpty {
                            self.cache[key] = finalText
                            Self.addToLookup(key)
                            self.saveCache()
                            HapticManager.shared.success()
                            continuation.finish()
                            return
                        } else {
                            self.summarySessionShort = nil
                            self.rewarmSession(.short)
                        }
                    } catch {
                        self.summarySessionShort = nil
                        self.rewarmSession(.short)
                        print("StreamSummary short error: \(error)")

                        let errorDesc = String(describing: error).lowercased()
                        if errorDesc.contains("guardrail") || errorDesc.contains("unsafe") || errorDesc.contains("sensitive") {
                            let blockedText = "Summary blocked by Apple"
                            self.cache[key] = blockedText
                            Self.addToLookup(key)
                            self.saveCache()
                            continuation.yield(blockedText)
                        }
                        continuation.finish()
                        return
                    }
                case .detailed:
                    // Detailed summaries (~200-250 words) - comprehensive summary for reader mode
                    let instructions = "Provide a comprehensive summary in 6-8 sentences (200-250 words). Cover the main thesis, key arguments, important facts, and conclusions. Be thorough but avoid repetition. No lists, no emojis."
                    var prompt = "Summarize this article comprehensively:\n\n"
                    if let seed = seedText?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !seed.isEmpty {
                        let s = String(seed.prefix(900))
                        prompt += "Preview/context from feed:\n\(s)\n\n"
                    }
                    // Use structure-aware slice with more content for detailed summaries
                    let primer = self.selectStructureAwareSlice(from: baseText, targetChars: 5000)
                    let promptPrimer = prompt + primer
                    do {
                        let session = self.summarySessionDetailed ?? LanguageModelSession(instructions: instructions)
                        if self.summarySessionDetailed == nil { self.summarySessionDetailed = session }

                        let streamDetailed = session.streamResponse(to: promptPrimer, generating: InlineSummary.self)
                        var finalText: String = ""
                        var revealedCount: Int = 0
                        let step = 2
                        let stepDelay: UInt64 = 20_000_000 // 20 ms
                        for try await partial in streamDetailed {
                            if Task.isCancelled { continuation.finish(); return }
                            guard let t = partial.content.text, !t.isEmpty else { continue }
                            finalText = t
                            if t.count <= revealedCount { continue }
                            var target = min(revealedCount + step, t.count)
                            while target < t.count {
                                let idx = t.index(t.startIndex, offsetBy: target)
                                let prefix = String(t[..<idx])
                                continuation.yield(prefix)
                                HapticManager.shared.typingHaptic()
                                revealedCount = target
                                try? await Task.sleep(nanoseconds: stepDelay)
                                if Task.isCancelled { continuation.finish(); return }
                                target = min(revealedCount + step, t.count)
                            }
                            continuation.yield(t)
                            HapticManager.shared.typingHaptic()
                            revealedCount = t.count
                        }
                        if !finalText.isEmpty {
                            self.cache[key] = finalText
                            Self.addToLookup(key)
                            self.saveCache()
                            HapticManager.shared.success()
                            continuation.finish()
                            return
                        } else {
                            self.summarySessionDetailed = nil
                            self.rewarmSession(.detailed)
                        }
                    } catch {
                        self.summarySessionDetailed = nil
                        self.rewarmSession(.detailed)
                        print("StreamSummary detailed error: \(error)")

                        let errorDesc = String(describing: error).lowercased()
                        if errorDesc.contains("guardrail") || errorDesc.contains("unsafe") || errorDesc.contains("sensitive") {
                            let blockedText = "Summary blocked by Apple"
                            self.cache[key] = blockedText
                            Self.addToLookup(key)
                            self.saveCache()
                            continuation.yield(blockedText)
                        }
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
        // Increased timeout from 3s to 10s to handle slower sites
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        let (data, _) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        return String(decoding: data, as: UTF8.self)
    }

    /// Fetch HTML with adaptive timeout - starts aggressive (5s), fails fast for slow sites
    /// This prevents one slow site from blocking all hero card generation
    func fetchHTMLWithAdaptiveTimeout(url: URL) async throws -> String {
        try Task.checkCancellation()

        // Use shorter timeout (5s) for hero cards - we have RSS description as fallback
        // This is faster than the standard 10s timeout
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 5)
        let (data, _) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated func extractReadableText(from html: String) -> String {
        if html.isEmpty { return "" }
        if Task.isCancelled { return "" }
        var s = String(html.prefix(200_000))
        if Task.isCancelled { return "" }

        // Use pre-compiled cached regex patterns for performance
        let ns = s as NSString
        var range = NSRange(location: 0, length: ns.length)

        // Remove HTML comments
        s = CachedRegex.htmlComments.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")

        // Try to extract just the article content
        range = NSRange(location: 0, length: (s as NSString).length)
        if let match = CachedRegex.articleTag.firstMatch(in: s, options: [], range: range) {
            let r = Range(match.range, in: s)!
            s = String(s[r])
        }
        if Task.isCancelled { return "" }

        // Remove structural blocks using cached regex
        range = NSRange(location: 0, length: (s as NSString).length)
        s = CachedRegex.navTag.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")
        range = NSRange(location: 0, length: (s as NSString).length)
        s = CachedRegex.headerTag.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")
        range = NSRange(location: 0, length: (s as NSString).length)
        s = CachedRegex.footerTag.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")
        range = NSRange(location: 0, length: (s as NSString).length)
        s = CachedRegex.asideTag.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")

        // Remove script and style tags
        range = NSRange(location: 0, length: (s as NSString).length)
        s = CachedRegex.scriptTag.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")
        if Task.isCancelled { return "" }
        range = NSRange(location: 0, length: (s as NSString).length)
        s = CachedRegex.styleTag.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")

        // Strip all remaining HTML tags
        range = NSRange(location: 0, length: (s as NSString).length)
        s = CachedRegex.anyHtmlTag.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")
        if Task.isCancelled { return "" }

        let attr = try? AttributedString(markdown: s)
        let plain = attr?.description ?? s

        // Collapse whitespace using cached regex
        let nsPlain = plain as NSString
        let collapsed = CachedRegex.whitespace.stringByReplacingMatches(in: plain, options: [], range: NSRange(location: 0, length: nsPlain.length), withTemplate: " ")
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

