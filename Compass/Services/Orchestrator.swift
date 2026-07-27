//
//  Orchestrator.swift
//  Compass
//
//  Top-level coordinator (ReAct-style: reason → act → observe → respond). It
//  wires the sub-agents into one pipeline and enforces the two hard rules:
//
//   1. Offline-first — web retrieval is attempted ONLY when the device is
//      online AND the user has enabled web search. Otherwise the answer is
//      generated entirely on-device.
//   2. Privacy — nothing leaves the device unless web search is explicitly
//      enabled by the user.
//
//  Pipeline: QueryPlanner → (RetrievalAgent → SynthesisAgent[grounded] →
//  VerifierAgent) | SynthesisAgent[local].
//

import Foundation

struct AnswerResult {
    let text: String
    let sources: [WebSource]
    /// True when the answer was grounded in retrieved web sources.
    let usedWebSearch: Bool
}

/// A snapshot of user/runtime config passed into the (nonisolated) pipeline so
/// the orchestrator itself doesn't touch main-actor state off the main actor.
struct OrchestrationConfig {
    let webSearchEnabled: Bool
    let isOnline: Bool
    let provider: SearchProvider
}

struct Orchestrator {
    let reasoner: LanguageReasoner

    func answer(
        question rawQuestion: String,
        conversationContext: String?,
        imageContext: String?,
        imageAttached: Bool = false,
        config: OrchestrationConfig
    ) async -> AnswerResult {
        let imageText = (imageContext ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImageText = !imageText.isEmpty

        // An image was attached but OCR found no text: don't hallucinate a
        // description — on-device analysis is text-only. Answer honestly.
        if imageAttached && !hasImageText {
            let msg = "I couldn't find any readable text in that image. I can read and answer questions about text in images — like notes, receipts, signs, or screenshots — but I can't describe a photo's contents on-device."
            return AnswerResult(text: msg, sources: [], usedWebSearch: false)
        }

        // Guard: an empty question with an image should still ask something.
        var question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if question.isEmpty && hasImageText { question = "What does this say and what does it mean?" }

        let planner = QueryPlanner(reasoner: reasoner)
        let plan = await planner.plan(for: question, hasImageContext: hasImageText, conversationContext: conversationContext)

        let canRetrieve = config.webSearchEnabled && config.isOnline && plan.needsRetrieval && !hasImageText && !imageAttached

        if canRetrieve {
            let retrieval = RetrievalAgent(provider: config.provider)
            let outcome = await retrieval.retrieve(plan: plan, originalQuery: question)

            if !outcome.sources.isEmpty {
                let synthesizer = SynthesisAgent(reasoner: reasoner)
                let draft = await synthesizer.synthesizeGrounded(
                    question: question,
                    conversationContext: conversationContext,
                    outcome: outcome
                )
                let verified = VerifierAgent().verify(text: ResponseCleaner.clean(draft), sources: outcome.sources)
                return AnswerResult(text: verified.text, sources: verified.sources, usedWebSearch: true)
            }
            // Retrieval found nothing usable → fall through to local answer.
        }

        // Local (on-device only) path — always available, including fully offline.
        let synthesizer = SynthesisAgent(reasoner: reasoner)
        let local = await synthesizer.synthesizeLocal(
            question: question,
            conversationContext: conversationContext,
            imageContext: imageContext
        )
        return AnswerResult(text: ResponseCleaner.clean(local), sources: [], usedWebSearch: false)
    }
}

/// Post-processing cleanup applied to every synthesized answer. On-device models
/// occasionally echo the "Assistant:" role label from the conversation context,
/// prefix a stray "1." enumerator, or leave a space before punctuation; this
/// removes those artifacts without altering real content or citations.
enum ResponseCleaner {
    static func clean(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return s }

        // Strip one or more leading role / answer labels.
        let labels = #"^(assistant|user|ai|answer|response)\s*[:\-]\s*"#
        while let range = s.range(of: labels, options: [.regularExpression, .caseInsensitive]) {
            s.removeSubrange(range)
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Remove stray placeholder citation tokens like "[N]", "[n]", "[#]"
        // that models sometimes emit literally instead of a real number.
        s = s.replacingOccurrences(of: #"\[\s*[A-Za-z#]\s*\]"#, with: "", options: .regularExpression)

        // Remove a stray leading enumerator ("1." / "1)") when the answer isn't
        // actually a multi-item list (no "2." / "2)" present).
        if s.range(of: #"^1[\.\)]\s+"#, options: .regularExpression) != nil,
           s.range(of: #"(^|\n)\s*2[\.\)]\s+"#, options: .regularExpression) == nil {
            s = s.replacingOccurrences(of: #"^1[\.\)]\s+"#, with: "", options: .regularExpression)
        }

        // Tidy spacing before punctuation and collapse repeated blank lines.
        s = s.replacingOccurrences(of: #" +([,.;:!?])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
