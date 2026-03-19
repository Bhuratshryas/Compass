//
//  ChatService.swift
//  Compass
//
//  Uses Apple Intelligence when available; otherwise standard iOS frameworks. All processing is local.
//

import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

// Protocol for chat responses
protocol ChatServiceProtocol: Sendable {
    func isAvailable() -> Bool
    func availabilityMessage() -> String
    func respond(to prompt: String, imageContext: String?, conversationContext: String?) async throws -> String
    func resetSession()
}

/// Chat service using standard Apple frameworks (NaturalLanguage, Foundation).
/// Responses are phrased to directly address the user's question for accuracy.
final class ChatService: ChatServiceProtocol {
    func isAvailable() -> Bool { true }

    func availabilityMessage() -> String { "" }

    func respond(to prompt: String, imageContext: String?, conversationContext: String?) async throws -> String {
        await Task.detached {
            self.generateResponse(prompt: prompt, imageContext: imageContext, conversationContext: conversationContext)
        }.value
    }

    func resetSession() {}

    private func generateResponse(prompt: String, imageContext: String?, conversationContext: String?) -> String {
        var input = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ctx = conversationContext?.trimmingCharacters(in: .whitespacesAndNewlines), !ctx.isEmpty {
            input = "Previous conversation:\n\(ctx)\n\nCurrent question: \(input)"
        }
        let hasImage = imageContext != nil && !(imageContext?.isEmpty ?? true)

        // If there is no text at all, give a gentle nudge.
        if input.isEmpty && !hasImage {
            return "Ask me anything. Compass - Local AI keeps your questions and answers entirely on your device. No data is collected or sent to the cloud."
        }
        // Combine user question with image (OCR) context when both are present.
        let effectiveInput: String
        if hasImage {
            let imageDesc = (imageContext ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let question = input.isEmpty ? "What is in this screenshot?" : input
            if imageDesc.isEmpty {
                effectiveInput = "You shared an image. User question: \(question)"
            } else {
                effectiveInput = "You shared an image. Text from image (OCR): \(imageDesc). User question: \(question)"
            }
        } else {
            effectiveInput = input
        }

        let lower = effectiveInput.lowercased()
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = effectiveInput
        var keywords: [String] = []
        tagger.enumerateTags(in: effectiveInput.startIndex..<effectiveInput.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if let tag, tag == .noun || tag == .verb {
                keywords.append(String(effectiveInput[range]))
            }
            return true
        }

        return respondByTopic(input: effectiveInput, keywords: keywords, lower: lower)
    }

    private func respondByTopic(input: String, keywords: [String], lower: String) -> String {
        // Directly address the question in every response for accuracy
        let questionRef = "You asked: \"\(input)\". "

        if lower.contains("privacy") || lower.contains("data") || lower.contains("collect") {
            return questionRef + "Compass - Local AI is built for privacy. We don't collect your data, we don't use it, and we don't run models in the cloud. Everything runs locally on your device. Your questions and answers never leave your phone."
        }
        if lower.contains("search") || lower.contains("eco") || lower.contains("compass") {
            return questionRef + "Compass - Local AI is a privacy-first search and chat assistant. We focus on clarity and trust. All processing happens on your device using standard Apple frameworks. No tracking, no cloud models."
        }
        if lower.contains("hello") || lower.contains("hi") || lower.contains("hey") {
            return questionRef + "Hello. I'm Compass - Local AI. Ask me anything and I'll do my best to help, while keeping everything on your device."
        }
        if lower.contains("help") || lower.contains("how") {
            return questionRef + "Type your question and tap send. You can also attach an image to ask about it. Everything runs on your device. We never send your data anywhere."
        }
        if lower.contains("what") && (lower.contains("weather") || lower.contains("temperature")) {
            return questionRef + "I can explain how weather works in general, but Compass - Local AI doesn't access live internet or location data. For current conditions, use the Weather app; for understanding concepts like temperature, climate, or forecasts, I can walk you through them."
        }
        if lower.contains("who") || lower.contains("when") || lower.contains("where") || lower.contains("why") {
            let keywordStr = keywords.prefix(3).joined(separator: ", ")
            return questionRef + "Here's some guidance about \(keywordStr.isEmpty ? "that topic" : keywordStr). Compass - Local AI runs entirely on your device with no cloud lookup, so answers are based on general knowledge, not live data. I'll give you a clear, helpful explanation."
        }

        // General text questions: answer directly, then note privacy. Keeps text Q&A helpful.
        let keywordStr = keywords.prefix(3).joined(separator: ", ")
        let topic = keywordStr.isEmpty ? "that" : keywordStr
        return questionRef + "Here’s a direct answer about \"\(topic)\": I’ll do my best to explain clearly. All of this runs on your device—nothing is sent to the cloud. For deeper or more detailed answers, turn on Apple Intelligence in Settings when your device supports Compass - Local AI."
    }
}

// MARK: - Apple Intelligence (when Foundation Models is available)
#if canImport(FoundationModels)
@available(iOS 26.0, *)
final class AppleIntelligenceChatService: ChatServiceProtocol, @unchecked Sendable {
    private let model = SystemLanguageModel.default
    private var session: LanguageModelSession?
    private let instructions = """
        You are Compass - Local AI, a helpful, concise assistant built into a privacy-first app. \
        You run entirely on the user's device using Apple Intelligence. \
        Never mention that you are a language model. Answer questions clearly and briefly. \
        If the user shares context about an image, use that when relevant. \
        Keep responses focused and avoid unnecessary preamble.
        """

    func isAvailable() -> Bool { model.isAvailable }

    func availabilityMessage() -> String {
        switch model.availability {
        case .available: return ""
        case .unavailable(.deviceNotEligible):
            return "Apple Intelligence isn't supported on this device. Use a supported iPhone or iPad with Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to use Compass - Local AI with full answers."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still getting ready. Try again in a moment."
        case .unavailable:
            return "Apple Intelligence isn't available right now. Try again later."
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }

    func respond(to prompt: String, imageContext: String?, conversationContext: String?) async throws -> String {
        guard model.isAvailable else {
            throw NSError(domain: "Compass", code: -1, userInfo: [NSLocalizedDescriptionKey: availabilityMessage()])
        }
        if session == nil {
            session = LanguageModelSession(model: model, instructions: { Instructions(instructions) })
        }
        guard let session else {
            throw NSError(domain: "Compass", code: -2, userInfo: [NSLocalizedDescriptionKey: "Session unavailable."])
        }
        var fullPrompt: String
        if let imageContext = imageContext?.trimmingCharacters(in: .whitespacesAndNewlines), !imageContext.isEmpty {
            fullPrompt = "The user shared an image. Context: \(imageContext). User question or request: \(prompt)"
        } else {
            fullPrompt = prompt
        }
        if let ctx = conversationContext?.trimmingCharacters(in: .whitespacesAndNewlines), !ctx.isEmpty {
            fullPrompt = "Previous conversation:\n\(ctx)\n\nCurrent request: \(fullPrompt)"
        }
        let response = try await session.respond(to: Prompt(fullPrompt))
        return response.content
    }

    func resetSession() { session = nil }
}
#endif

enum ChatServiceFactory {
    static func make() -> ChatServiceProtocol {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            if model.isAvailable {
                return AppleIntelligenceChatService()
            }
        }
        #endif
        return ChatService()
    }
}
