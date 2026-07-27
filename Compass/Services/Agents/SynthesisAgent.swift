//
//  SynthesisAgent.swift
//  Compass
//
//  Stages 4-5 (constrained generation). Produces the final answer.
//   - Grounded mode: the LLM synthesizes ONLY from retrieved evidence and must
//     attach inline [N] citation markers (Perplexity-style constrained
//     synthesis). Without an LLM, we do extractive synthesis from the snippets.
//   - Local mode: on-device knowledge answer (no web), used offline or when the
//     planner decided retrieval isn't needed.
//

import Foundation
import NaturalLanguage

struct SynthesisAgent {
    let reasoner: LanguageReasoner

    private static let groundedSystem = """
    You are Compass - Local AI, a concise, trustworthy assistant. Answer the \
    user's question in your own words using ONLY the numbered sources provided. \
    Attach an inline citation using the source's real number, like [1] or [2], \
    to each factual claim. Never write the literal letter "N" in brackets. Do \
    not just repeat a source's title — write a real sentence that answers the \
    question. If the sources don't contain the answer, say so plainly. Do not \
    invent citations or facts.
    """

    private static let localSystem = """
    You are Compass - Local AI, a helpful, concise on-device assistant. You run \
    entirely on the user's device with no internet access for this answer. \
    Answer clearly from general knowledge. If the question requires up-to-date \
    or real-time information you cannot verify offline, say so briefly. Never \
    claim to have browsed the web.
    """

    // MARK: - Grounded (with retrieved evidence)

    func synthesizeGrounded(question: String, conversationContext: String?, outcome: RetrievalOutcome) async -> String {
        guard !outcome.evidence.isEmpty else {
            return await synthesizeLocal(question: question, conversationContext: conversationContext, imageContext: nil)
        }

        if reasoner.isAvailable {
            var prompt = ""
            if let ctx = conversationContext?.trimmingCharacters(in: .whitespacesAndNewlines), !ctx.isEmpty {
                prompt += "Conversation so far:\n\(ctx)\n\n"
            }
            prompt += "Sources:\n" + outcome.evidence.joined(separator: "\n") + "\n\n"
            prompt += "Question: \(question)\n\nWrite a clear answer with inline numbered citations:"
            if let reply = try? await reasoner.respond(system: Self.groundedSystem, prompt: prompt),
               isUsableGroundedReply(reply, outcome: outcome) {
                return reply
            }
        }
        return extractiveSynthesis(question: question, outcome: outcome)
    }

    /// Reject replies that are too short, refuse, or merely echo a source title,
    /// so we fall back to a grounded extractive answer instead.
    private func isUsableGroundedReply(_ reply: String, outcome: RetrievalOutcome) -> Bool {
        let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        // Strip citation markers to measure real content length.
        let withoutMarkers = cleaned
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if withoutMarkers.count < 40 { return false }

        let lower = withoutMarkers.lowercased()
        let refusals = ["i cannot", "i can't", "i'm unable", "i am unable",
                        "i don't have", "i do not have", "sorry, i", "sorry i"]
        if refusals.contains(where: { lower.hasPrefix($0) }) { return false }

        // Reject if the whole answer is basically one source's title.
        for source in outcome.sources {
            let title = source.title.lowercased()
            if !title.isEmpty && (lower == title || (lower.contains(title) && withoutMarkers.count < title.count + 15)) {
                return false
            }
        }
        return true
    }

    /// Deterministic fallback: stitch the top snippets into a readable answer
    /// with [N] markers so the citations remain meaningful without an LLM.
    private func extractiveSynthesis(question: String, outcome: RetrievalOutcome) -> String {
        let sentences = outcome.sources.prefix(3).map { source -> String in
            let snippet = trimToSentence(source.snippet)
            return "\(snippet) [\(source.id)]"
        }
        let body = sentences.joined(separator: " ")
        if body.trimmingCharacters(in: .whitespaces).isEmpty {
            return "I found sources but couldn't extract a clear answer. See the references below."
        }
        return "Based on the sources I found: \(body)"
    }

    // MARK: - Local (on-device only)

    func synthesizeLocal(question: String, conversationContext: String?, imageContext: String?) async -> String {
        if reasoner.isAvailable {
            var prompt = ""
            if let ctx = conversationContext?.trimmingCharacters(in: .whitespacesAndNewlines), !ctx.isEmpty {
                prompt += "Conversation so far:\n\(ctx)\n\n"
            }
            if let img = imageContext?.trimmingCharacters(in: .whitespacesAndNewlines), !img.isEmpty {
                prompt += "The user attached an image. Text extracted from it (OCR): \(img)\n\n"
            }
            prompt += "Question: \(question)"
            if let reply = try? await reasoner.respond(system: Self.localSystem, prompt: prompt),
               !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return reply
            }
        }
        return heuristicLocalAnswer(question: question, imageContext: imageContext)
    }

    // MARK: - Heuristic local answer (no LLM available)

    private func heuristicLocalAnswer(question: String, imageContext: String?) -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if let img = imageContext?.trimmingCharacters(in: .whitespacesAndNewlines), !img.isEmpty {
            return "Here's the text I read from your image:\n\n\"\(img)\"\n\nEverything was processed on your device. Ask a follow-up question about it and I'll help."
        }
        if trimmed.isEmpty {
            return "Ask me anything. Compass - Local AI keeps your questions and answers on your device."
        }
        if ["hi", "hello", "hey"].contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) {
            return "Hello. I'm Compass - Local AI. Ask me anything — everything stays on your device. Turn on web search in Settings if you'd like cited answers from the internet."
        }

        let keywords = keywords(from: trimmed).prefix(3).joined(separator: ", ")
        let topic = keywords.isEmpty ? "that" : keywords
        return "This device doesn't have Apple Intelligence enabled, so I'm giving a general on-device answer about \(topic). For detailed, cited answers, enable Apple Intelligence in Settings, or turn on web search in Compass Settings while online. Nothing you type leaves your device unless you enable web search."
    }

    private func keywords(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var out: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            if let tag, tag == .noun || tag == .verb { out.append(String(text[range])) }
            return true
        }
        return out
    }

    private func trimToSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 240 { return trimmed }
        let cut = String(trimmed.prefix(240))
        if let lastPeriod = cut.range(of: ".", options: .backwards) {
            return String(cut[..<lastPeriod.upperBound])
        }
        return cut + "…"
    }
}
