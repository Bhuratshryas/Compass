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
    private let memory: ConversationMemory
    private var didCreateTitle = false
    private var inFlightTask: Task<Void, Never>?

    init(chatService: ChatServiceProtocol, store: ConversationStore, conversationId: UUID, initialMessages: [ChatMessage] = []) {
        self.chatService = chatService
        self.store = store
        self.conversationId = conversationId
        self.messages = initialMessages
        self.memory = ConversationMemory(reasoner: ReasonerFactory.make())
    }

    /// Send a message and append the response. Thread supports multiple Q&A in one conversation; messages are never cleared until the user starts a new chat.
    func send() {
        // Cancel any previous in-flight work before starting a new request.
        inFlightTask?.cancel()

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

        // Build runtime config on the main actor before entering the pipeline.
        let base = text.isEmpty ? defaultImageQuestion : text
        let config = OrchestrationConfig(
            webSearchEnabled: AppSettings.shared.webSearchEnabled,
            isOnline: NetworkMonitor.shared.isOnline,
            provider: SearchProviderFactory.make()
        )

        inFlightTask = Task {
            // When there's an image, always run Apple's OCR and send that text as image context.
            var imageContext: String? = nil
            if let imageToSend {
                imageContext = await extractText(from: imageToSend.data)
                if let ctx = imageContext, ctx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    imageContext = nil
                }
            }

            // Preserve context across long sessions: combine a rolling summary of
            // older turns, semantically recalled earlier messages, and the recent
            // buffer — instead of a flat "last 10 messages" window.
            let (priorMessages, storedSummary, storedWatermark) = await MainActor.run {
                () -> ([ChatMessage], String, Int) in
                let prior = Array(self.messages.dropLast(1))
                let conv = self.store.conversation(by: self.conversationId)
                return (prior, conv?.summary ?? "", conv?.memoryWatermark ?? 0)
            }
            let conversationContext = self.memory.buildContext(
                history: priorMessages,
                summary: storedSummary,
                watermark: storedWatermark,
                query: base
            )

            if Task.isCancelled {
                await MainActor.run {
                    isLoading = false
                    saveToStore()
                }
                return
            }

            // Single orchestrated request (no racy parallel session mutation).
            let result = await chatService.respond(
                to: base,
                imageContext: imageContext,
                imageAttached: imageToSend != nil,
                conversationContext: conversationContext,
                config: config
            )
            if Task.isCancelled {
                await MainActor.run {
                    isLoading = false
                    saveToStore()
                }
                return
            }
            await animateAssistantResponse(result.text, sources: result.sources)

            // Fold aged-out turns into long-term memory so future turns in this
            // (possibly very long) session still remember earlier facts.
            await self.updateMemoryIfNeeded()
        }
    }

    /// Update the persisted rolling summary once enough turns have aged out of the
    /// recent buffer. Runs off the critical path (after the reply is shown).
    private func updateMemoryIfNeeded() async {
        let (snapshot, summary, watermark) = await MainActor.run {
            () -> ([ChatMessage], String, Int) in
            let conv = self.store.conversation(by: self.conversationId)
            return (self.messages, conv?.summary ?? "", conv?.memoryWatermark ?? 0)
        }
        guard let updated = await memory.maintain(messages: snapshot, summary: summary, watermark: watermark) else {
            return
        }
        await MainActor.run {
            self.store.update(id: self.conversationId, summary: updated.summary, memoryWatermark: updated.watermark)
        }
    }

    func stop() {
        inFlightTask?.cancel()
        inFlightTask = nil
        isLoading = false
        saveToStore()
    }

    func clearChat() {
        inFlightTask?.cancel()
        inFlightTask = nil
        messages = []
        errorMessage = nil
        didCreateTitle = false
    }

    private func saveToStore(title: String? = nil) {
        let existing = store.conversation(by: conversationId)
        let titleToUse = title ?? existing?.title ?? "New chat"
        let conv = Conversation(
            id: conversationId,
            title: titleToUse,
            messages: messages,
            createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date(),
            summary: existing?.summary ?? "",
            memoryWatermark: existing?.memoryWatermark ?? 0
        )
        store.save(conv)
    }

    /// Animate the assistant response word by word for a more conversational feel.
    private func animateAssistantResponse(_ fullText: String, sources: [WebSource] = []) async {
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await MainActor.run {
                isLoading = false
                saveToStore()
            }
            return
        }

        let words = trimmed.split(separator: " ")
        var message = ChatMessage(role: .assistant, content: "", sources: sources)

        await MainActor.run {
            messages.append(message)
            isLoading = false
            saveToStore()
        }

        for (index, word) in words.enumerated() {
            if Task.isCancelled { break }
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
                            // Preserve layout (rows/columns) instead of flattening
                            // to a single space-joined string.
                            let fragments = observations.compactMap { obs -> OCRTextBuilder.Fragment? in
                                guard let text = obs.topCandidates(1).first?.string else { return nil }
                                return OCRTextBuilder.Fragment(text: text, box: obs.boundingBox)
                            }
                            let assembled = OCRTextBuilder.assemble(fragments)
                            if !assembled.isEmpty { result = assembled }
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
