//
//  ChatViewModel.swift
//  Compass
//

import Foundation
import SwiftUI
import UIKit
import Vision

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var attachedImage: ChatMessage.ImageAttachment?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    let conversationId: UUID
    private let chatService: ChatServiceProtocol
    private let store: ConversationStore
    private var didCreateTitle = false

    init(chatService: ChatServiceProtocol, store: ConversationStore, conversationId: UUID, initialMessages: [ChatMessage] = []) {
        self.chatService = chatService
        self.store = store
        self.conversationId = conversationId
        self.messages = initialMessages
    }

    /// Send a message and append the response. Thread supports multiple Q&A in one conversation; messages are never cleared until the user starts a new chat.
    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || attachedImage != nil else { return }

        // What we show in the chat as the user's message.
        let defaultImageQuestion = "What is in this screenshot?"
        let userContent = text.isEmpty ? defaultImageQuestion : text
        let userMessage = ChatMessage(
            role: .user,
            content: userContent,
            attachedImage: attachedImage
        )
        messages.append(userMessage)
        inputText = ""  // Clear the input as soon as we send
        let imageToSend = attachedImage
        attachedImage = nil
        isLoading = true
        errorMessage = nil

        if !didCreateTitle {
            didCreateTitle = true
            let title = Conversation.title(from: userContent)
            saveToStore(title: title)
        }

        Task {
            // When there's an image, always run Apple's OCR and send that text as image context.
            var imageContext: String? = nil
            if let imageToSend {
                imageContext = await extractText(from: imageToSend.data)
                if let ctx = imageContext, ctx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    imageContext = nil
                }
            }

            let base = text.isEmpty ? defaultImageQuestion : text
            let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count

            // Build a set of prompt variants. The model sees these; the user never does.
            var prompts: [String] = []
            if wordCount > 0 && wordCount <= 3 {
                prompts.append("What is a \(base)?")
                prompts.append("Can you share more about \(base)?")
                prompts.append("Explain \(base) in simple terms.")
                prompts.append("Give a clear, detailed answer: what does \(base) mean?")
            } else {
                prompts.append(base)
                prompts.append("Please answer this clearly and in detail: \(base)")
            }

            let response = await bestResponse(prompts: prompts, imageContext: imageContext)
            await animateAssistantResponse(response)
        }
    }

    func clearChat() {
        chatService.resetSession()
        messages = []
        errorMessage = nil
        didCreateTitle = false
    }

    private func saveToStore(title: String? = nil) {
        let titleToUse = title ?? store.conversation(by: conversationId)?.title ?? "New chat"
        let conv = Conversation(
            id: conversationId,
            title: titleToUse,
            messages: messages,
            createdAt: store.conversation(by: conversationId)?.createdAt ?? Date(),
            updatedAt: Date()
        )
        store.save(conv)
    }

    /// Animate the assistant response word by word for a more conversational feel.
    private func animateAssistantResponse(_ fullText: String) async {
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await MainActor.run {
                isLoading = false
                saveToStore()
            }
            return
        }

        let words = trimmed.split(separator: " ")
        var message = ChatMessage(role: .assistant, content: "")

        await MainActor.run {
            messages.append(message)
            isLoading = false
            saveToStore()
        }

        for (index, word) in words.enumerated() {
            try? await Task.sleep(nanoseconds: 40_000_000) // 40ms per word
            await MainActor.run {
                guard let i = messages.firstIndex(where: { $0.id == message.id }) else { return }
                let prefix = messages[i].content.isEmpty ? "" : " "
                messages[i].content += prefix + word
                message = messages[i]
                if index == words.count - 1 {
                    saveToStore()
                }
            }
        }
    }

    /// Fire all prompt variants in parallel, return the first good response.
    /// If none are good, return the longest one. If all fail, return a fallback message.
    private func bestResponse(prompts: [String], imageContext: String?) async -> String {
        let service = chatService

        // Run all prompts concurrently; collect results as they arrive.
        let results: [(String, String?)] = await withTaskGroup(of: (String, String?).self, returning: [(String, String?)].self) { group in
            for prompt in prompts {
                group.addTask {
                    service.resetSession()
                    let reply = try? await service.respond(to: prompt, imageContext: imageContext)
                    return (prompt, reply)
                }
            }
            var collected: [(String, String?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Pick the best: first good response (long enough, not a refusal).
        let replies = results.compactMap { $0.1 }
        if let good = replies.first(where: { isGoodResponse($0) }) {
            return good
        }
        // If no "good" one, take the longest non-empty one.
        if let longest = replies.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            .max(by: { $0.count < $1.count }) {
            return longest
        }
        return "I wasn't able to answer that. Please try rephrasing your question."
    }

    /// Heuristic: a response is "good" if it's long enough and doesn't look like a refusal.
    private func isGoodResponse(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 20 { return false }
        let lower = trimmed.lowercased()
        let refusals = ["i can't", "i cannot", "i'm unable", "i am unable", "sorry, i",
                        "i don't have", "i do not have", "not able to help",
                        "couldn't complete", "could not complete"]
        for refusal in refusals {
            if lower.hasPrefix(refusal) { return false }
        }
        return true
    }

    /// Run on-device OCR for an attached image and return detected text (if any).
    private func extractText(from data: Data) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: String?
                if let image = UIImage(data: data), let cgImage = image.cgImage {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    do {
                        try handler.perform([request])
                        if let observations = request.results {
                            let strings = observations.compactMap { $0.topCandidates(1).first?.string }
                            if !strings.isEmpty {
                                result = strings.joined(separator: " ")
                            }
                        }
                    } catch {
                        // Ignore OCR errors; we'll fall back to the default question.
                    }
                }
                continuation.resume(returning: result)
            }
        }
    }
}
