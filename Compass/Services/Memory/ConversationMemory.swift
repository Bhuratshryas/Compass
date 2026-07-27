import Foundation
import NaturalLanguage

/// Long-session memory for Compass.
///
/// On-device models have a small context window, so we can't just paste the
/// whole transcript. Instead we combine three research-backed techniques:
///
///  1. **Recent buffer** — the last `recentBufferCount` messages are always kept
///     verbatim (recency dominates conversational coherence).
///  2. **Rolling summary memory** — messages older than the buffer are folded
///     into a compact, persisted summary (a "summary buffer memory"), so durable
///     facts survive indefinitely and across app restarts.
///  3. **Semantic recall** — the specific older messages most relevant to the
///     current question are retrieved via on-device embeddings and re-injected
///     verbatim, so precise details aren't lost to summarization.
///
/// The assembled context is capped to `maxContextChars` so it never overflows
/// the model. Everything here runs fully on-device.
struct ConversationMemory {
    let reasoner: LanguageReasoner

    /// Messages kept verbatim at the tail of the conversation.
    var recentBufferCount = 8
    /// Only fold into the summary once this many new messages have aged out of
    /// the buffer, to avoid re-summarizing on every single turn.
    var foldBatch = 4
    /// Hard cap on the assembled context handed to the model.
    var maxContextChars = 3500
    /// Hard cap on the rolling summary length.
    var maxSummaryChars = 800
    /// How many older messages to pull back via semantic recall.
    var recallCount = 3
    /// Minimum cosine similarity for a recalled message to be relevant.
    var recallThreshold = 0.35

    private let embedding = NLEmbedding.wordEmbedding(for: .english)

    // MARK: - Context assembly (per turn)

    /// Build the context string for the model given the conversation history
    /// (everything before the current user question), the persisted rolling
    /// summary, its watermark, and the current query (for semantic recall).
    func buildContext(history: [ChatMessage], summary: String, watermark: Int, query: String) -> String? {
        let w = min(max(watermark, 0), history.count)
        let summarized = Array(history[0..<w])       // only present via `summary`
        let verbatim = Array(history[w...])          // recent, shown in full

        var sections: [String] = []

        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSummary.isEmpty {
            sections.append("Memory of earlier conversation:\n\(trimmedSummary)")
        }

        // Pull back specific earlier messages relevant to the new question.
        let recalled = semanticRecall(query: query, from: summarized)
        if !recalled.isEmpty {
            sections.append("Relevant earlier messages:\n" + recalled.map(line).joined(separator: "\n"))
        }

        if !verbatim.isEmpty {
            sections.append("Recent messages:\n" + verbatim.map(line).joined(separator: "\n"))
        }

        guard !sections.isEmpty else { return nil }

        var ctx = sections.joined(separator: "\n\n")
        // Keep the most recent content if we blow the budget (summary is already
        // capped, so the tail here is the recent buffer — the part we least want
        // to lose).
        if ctx.count > maxContextChars {
            ctx = "…\n" + String(ctx.suffix(maxContextChars))
        }
        return ctx
    }

    // MARK: - Maintenance (after each reply)

    /// Fold aged-out messages into the rolling summary. Returns the updated
    /// `(summary, watermark)` or `nil` when there's nothing to fold yet.
    func maintain(messages: [ChatMessage], summary: String, watermark: Int) async -> (summary: String, watermark: Int)? {
        let w = min(max(watermark, 0), messages.count)
        // Everything except the recent buffer should eventually be summarized.
        let target = max(w, messages.count - recentBufferCount)
        guard target - w >= foldBatch else { return nil }

        let newMessages = Array(messages[w..<target])
        guard !newMessages.isEmpty else { return nil }

        let updated = await fold(priorSummary: summary, newMessages: newMessages)
        return (updated, target)
    }

    // MARK: - Summarization

    private func fold(priorSummary: String, newMessages: [ChatMessage]) async -> String {
        let transcript = newMessages.map(line).joined(separator: "\n")

        if reasoner.isAvailable {
            let system = """
            You maintain a running memory of a conversation between a user and an \
            assistant. Given the existing memory and new messages, produce an \
            UPDATED memory of at most 120 words. Preserve durable facts: the \
            user's name, stated preferences, goals, decisions, constraints, and \
            key topics/entities discussed. Merge new facts with old; drop \
            pleasantries and resolved small talk. Output ONLY the memory text.
            """
            var prompt = ""
            let prior = priorSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !prior.isEmpty { prompt += "Existing memory:\n\(prior)\n\n" }
            prompt += "New messages:\n\(transcript)\n\nUpdated memory:"
            if let reply = try? await reasoner.respond(system: system, prompt: prompt) {
                let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.count >= 8 {
                    return String(cleaned.prefix(maxSummaryChars))
                }
            }
        }
        return heuristicFold(priorSummary: priorSummary, newMessages: newMessages)
    }

    /// No-LLM fallback: retain the prior memory and append the salient facts
    /// (user statements + named entities) from the new messages.
    private func heuristicFold(priorSummary: String, newMessages: [ChatMessage]) -> String {
        var parts: [String] = []
        let prior = priorSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prior.isEmpty { parts.append(prior) }

        let userStatements = newMessages
            .filter { $0.role == .user }
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !userStatements.isEmpty {
            parts.append("User said: " + userStatements.prefix(6).joined(separator: " | "))
        }

        let entities = newMessages
            .flatMap { QueryPlanner.entities(in: $0.content) }
        if !entities.isEmpty {
            let unique = Array(NSOrderedSet(array: entities)).compactMap { $0 as? String }
            parts.append("Topics: " + unique.prefix(8).joined(separator: ", "))
        }

        // Keep the earliest facts when capping: recency is already covered by the
        // verbatim recent buffer, so the summary's job is to preserve the older
        // durable facts that would otherwise be lost.
        let joined = parts.joined(separator: " ")
        return String(joined.prefix(maxSummaryChars))
    }

    // MARK: - Semantic recall

    private func semanticRecall(query: String, from messages: [ChatMessage]) -> [ChatMessage] {
        guard !messages.isEmpty, recallCount > 0 else { return [] }
        let queryVector = averagedVector(for: tokenize(query))
        guard queryVector != nil else { return [] }

        var scored: [(msg: ChatMessage, score: Double, index: Int)] = []
        for (index, msg) in messages.enumerated() {
            let text = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let vec = averagedVector(for: tokenize(text))
            let score = cosine(queryVector, vec) ?? 0
            if score >= recallThreshold {
                scored.append((msg, score, index))
            }
        }
        guard !scored.isEmpty else { return [] }

        // Take the top matches, then restore chronological order for readability.
        let top = scored.sorted { $0.score > $1.score }.prefix(recallCount)
        return top.sorted { $0.index < $1.index }.map { $0.msg }
    }

    // MARK: - Embedding helpers

    private func averagedVector(for tokens: [String]) -> [Double]? {
        guard let embedding, !tokens.isEmpty else { return nil }
        var sum: [Double]? = nil
        var count = 0
        for token in tokens {
            guard let vec = embedding.vector(for: token) else { continue }
            if sum == nil { sum = [Double](repeating: 0, count: vec.count) }
            guard var s = sum, s.count == vec.count else { continue }
            for i in 0..<vec.count { s[i] += vec[i] }
            sum = s
            count += 1
        }
        guard var result = sum, count > 0 else { return nil }
        for i in 0..<result.count { result[i] /= Double(count) }
        return result
    }

    private func cosine(_ a: [Double]?, _ b: [Double]?) -> Double? {
        guard let a, let b, a.count == b.count, !a.isEmpty else { return nil }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return nil }
        return dot / (sqrt(na) * sqrt(nb))
    }

    private func tokenize(_ text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var tokens: [String] = []
        let stopwords: Set<String> = ["the", "a", "an", "of", "to", "in", "on", "for",
            "and", "or", "is", "are", "was", "were", "be", "with", "at", "by", "it",
            "this", "that", "as", "from", "what", "which", "who", "how", "my", "your"]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace, .omitOther]) { _, range in
            let token = text[range].lowercased()
            if token.count > 1 && !stopwords.contains(token) {
                tokens.append(token)
            }
            return true
        }
        return tokens
    }

    private func line(_ msg: ChatMessage) -> String {
        let label = msg.role == .user ? "User" : "Assistant"
        return "\(label): \(msg.content)"
    }
}
