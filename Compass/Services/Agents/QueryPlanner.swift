//
//  QueryPlanner.swift
//  Compass
//
//  Stage 1 of the pipeline (query understanding). Decides whether an answer
//  needs fresh/external information (web retrieval) or can be answered from the
//  model's own knowledge, and decomposes the request into focused sub-queries
//  to improve retrieval recall (Plan-and-Solve style decomposition).
//
//  Routing is deterministic (heuristics) so behavior is predictable and cheap.
//  For follow-up turns ("when did he die?"), the planner folds entities from the
//  recent conversation into the search sub-queries so retrieval stays on-topic.
//

import Foundation
import NaturalLanguage

struct QueryPlan {
    let needsRetrieval: Bool
    let subQueries: [String]
    let isConversational: Bool
}

struct QueryPlanner {
    let reasoner: LanguageReasoner

    /// Cues that imply the answer depends on current / external facts.
    private static let freshnessCues: [String] = [
        "latest", "current", "today", "tonight", "now", "recent", "recently",
        "news", "update", "price", "stock", "score", "weather", "release",
        "released", "who won", "how much", "this year", "this week", "upcoming",
        "schedule", "when is", "when does", "when did", "deadline", "version"
    ]

    /// Superlatives usually target a specific verifiable fact.
    private static let superlativeCues: [String] = [
        "tallest", "largest", "biggest", "highest", "smallest", "longest",
        "shortest", "fastest", "slowest", "richest", "oldest", "newest",
        "best", "worst", "most", "greatest", "world record", "who won"
    ]

    private static let interrogatives: [String] = [
        "who", "what", "when", "where", "which", "whose", "whom"
    ]

    private static let conversationalCues: [String] = [
        "hello", "hi", "hey", "thanks", "thank you", "bye", "good morning",
        "good night", "how are you", "what's up", "yo", "sup"
    ]

    private static let pronouns: Set<String> = [
        "he", "she", "it", "they", "them", "their", "theirs", "its", "his",
        "her", "hers", "him", "this", "that", "those", "these", "there"
    ]

    func plan(for query: String, hasImageContext: Bool, conversationContext: String?) async -> QueryPlan {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count

        let isConversational = Self.conversationalCues.contains { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + ",") || lower.hasPrefix($0 + "!") }
            && wordCount <= 4

        // Image questions are answered from OCR context, not the web.
        if hasImageContext {
            return QueryPlan(needsRetrieval: false, subQueries: trimmed.isEmpty ? [] : [trimmed], isConversational: isConversational)
        }
        if isConversational || trimmed.isEmpty {
            return QueryPlan(needsRetrieval: false, subQueries: trimmed.isEmpty ? [] : [trimmed], isConversational: isConversational)
        }

        let hasFreshness = Self.freshnessCues.contains { lower.contains($0) }
        let hasSuperlative = Self.superlativeCues.contains { lower.contains($0) }
        let hasYear = lower.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil
        let hasEntity = containsEntity(trimmed)
        let isFollowUp = Self.isFollowUp(lower: lower, wordCount: wordCount)

        // Retrieve for time-sensitive info, superlatives, or questions about a
        // specific named entity. Definitional / conceptual questions with no
        // entity (e.g. "explain photosynthesis", "what is entropy") stay
        // on-device. Follow-ups inherit intent from the prior turn's entities.
        let contextEntities = Self.entities(in: conversationContext)
        let followUpNeedsRetrieval = isFollowUp && !contextEntities.isEmpty
            && (hasFreshness || Self.interrogatives.contains { lower.hasPrefix($0) })

        let needsRetrieval = hasFreshness || hasSuperlative || hasYear || hasEntity || followUpNeedsRetrieval

        var subQueries = heuristicSubQueries(from: trimmed)

        // For short pronoun follow-ups ("when did he die?"), fold the
        // conversation's entities into the search query so retrieval stays on
        // topic. Restricted to ≤4 words so topic-shifting follow-ups (e.g.
        // "what is their latest iPhone?") aren't polluted by prior entities.
        if needsRetrieval, isFollowUp, wordCount <= 4, !contextEntities.isEmpty {
            let entityPrefix = contextEntities.prefix(2).joined(separator: " ")
            subQueries.insert("\(entityPrefix) \(trimmed)", at: 0)
        }

        if needsRetrieval, reasoner.isAvailable {
            let contextForRefine = isFollowUp ? conversationContext : nil
            if let refined = try? await refineQueries(original: trimmed, context: contextForRefine), !refined.isEmpty {
                subQueries = dedupe(subQueries + refined)
            }
        }
        return QueryPlan(needsRetrieval: needsRetrieval, subQueries: dedupe(subQueries), isConversational: false)
    }

    // MARK: - Heuristic decomposition

    private func heuristicSubQueries(from query: String) -> [String] {
        var queries = [query]
        let parts = query.components(separatedBy: CharacterSet(charactersIn: "?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.split(separator: " ").count >= 3 }
        if parts.count > 1 { queries.append(contentsOf: parts) }
        return dedupe(queries)
    }

    // MARK: - Optional LLM refinement

    private func refineQueries(original: String, context: String?) async throws -> [String] {
        let system = "You rewrite a user's question into 1-3 concise, self-contained web-search queries. Resolve pronouns using the conversation if provided. Output ONLY the queries, one per line, no numbering, no commentary."
        var prompt = ""
        if let context, !context.isEmpty { prompt += "Conversation:\n\(context)\n\n" }
        prompt += "Question: \(original)\nSearch queries:"
        let raw = try await reasoner.respond(system: system, prompt: prompt)
        let lines = raw
            .split(whereSeparator: \.isNewline)
            .map { line -> String in
                var s = String(line).trimmingCharacters(in: .whitespaces)
                while let first = s.first, first.isNumber || first == "." || first == "-" || first == "•" || first == ")" {
                    s.removeFirst()
                    s = s.trimmingCharacters(in: .whitespaces)
                }
                return s
            }
            .filter { $0.count > 2 }
        return Array(lines.prefix(3))
    }

    // MARK: - Entity detection

    private func containsEntity(_ text: String) -> Bool {
        if Self.nameTaggerFindsEntity(text) { return true }
        return !Self.capitalizedEntities(in: text).isEmpty
    }

    private static func nameTaggerFindsEntity(_ text: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var found = false
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitPunctuation, .omitWhitespace]) { tag, _ in
            if let tag, tag == .personalName || tag == .placeName || tag == .organizationName {
                found = true
                return false
            }
            return true
        }
        return found
    }

    /// Capitalized tokens that look like named entities. A capitalized word that
    /// isn't the first token is a strong signal; a short (≤2 word) query led by a
    /// capitalized word (e.g. "Everest") also counts.
    private static func capitalizedEntities(in text: String) -> [String] {
        let labelStop: Set<String> = ["User", "Assistant", "AI", "The", "A", "An",
            "Who", "What", "When", "Where", "Why", "Which", "How", "Can", "Is",
            "Are", "Do", "Does", "Tell", "Explain", "Define", "Give", "Please"]
        let rawTokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var entities: [String] = []
        for (index, raw) in rawTokens.enumerated() {
            let word = raw.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard word.count >= 3, let first = word.first, first.isUppercase, !first.isNumber else { continue }
            if labelStop.contains(word) { continue }
            if index > 0 || rawTokens.count <= 2 {
                entities.append(word)
            }
        }
        return entities
    }

    static func entities(in context: String?) -> [String] {
        guard let context, !context.isEmpty else { return [] }
        var seen = Set<String>()
        var ordered: [String] = []
        // Prefer entities from the most recent lines.
        for line in context.split(whereSeparator: \.isNewline).suffix(4).reversed() {
            for entity in capitalizedEntities(in: String(line)) {
                let key = entity.lowercased()
                if seen.contains(key) { continue }
                seen.insert(key)
                ordered.append(entity)
            }
        }
        return ordered
    }

    private static func isFollowUp(lower: String, wordCount: Int) -> Bool {
        let tokens = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if tokens.contains(where: { pronouns.contains($0) }) { return true }
        return wordCount <= 4
    }

    // MARK: - Helpers

    private func dedupe(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in items {
            let key = item.lowercased()
            if key.isEmpty || seen.contains(key) { continue }
            seen.insert(key)
            out.append(item)
        }
        return out
    }
}
