//
//  ChatService.swift
//  Compass
//
//  Thin entry point in front of the multi-agent Orchestrator. Apple
//  Intelligence is used as the on-device reasoner/synthesizer when available;
//  otherwise a heuristic reasoner keeps the app fully functional offline. All
//  routing, retrieval, ranking, synthesis and citation verification live in the
//  agents under Services/Agents.
//

import Foundation

protocol ChatServiceProtocol: Sendable {
    /// Human-readable name of the active reasoner (e.g. "Apple Intelligence").
    var reasonerName: String { get }
    /// Whether the higher-quality on-device model (Apple Intelligence) is active.
    var hasAppleIntelligence: Bool { get }

    /// Produce a grounded or on-device answer. Never throws: the orchestrator
    /// always degrades to a local answer rather than failing.
    func respond(
        to prompt: String,
        imageContext: String?,
        imageAttached: Bool,
        conversationContext: String?,
        config: OrchestrationConfig
    ) async -> AnswerResult
}

struct CompassChatService: ChatServiceProtocol {
    private let reasoner: LanguageReasoner
    private let orchestrator: Orchestrator

    init() {
        let reasoner = ReasonerFactory.make()
        self.reasoner = reasoner
        self.orchestrator = Orchestrator(reasoner: reasoner)
    }

    var reasonerName: String { reasoner.displayName }
    var hasAppleIntelligence: Bool { reasoner.isAvailable }

    func respond(
        to prompt: String,
        imageContext: String?,
        imageAttached: Bool,
        conversationContext: String?,
        config: OrchestrationConfig
    ) async -> AnswerResult {
        await orchestrator.answer(
            question: prompt,
            conversationContext: conversationContext,
            imageContext: imageContext,
            imageAttached: imageAttached,
            config: config
        )
    }
}

enum ChatServiceFactory {
    static func make() -> ChatServiceProtocol { CompassChatService() }
}
