//
//  LanguageReasoner.swift
//  Compass
//
//  A thin abstraction over the on-device LLM so the orchestration agents don't
//  depend on FoundationModels directly. When Apple Intelligence is available we
//  use it for synthesis and (optional) query reformulation. When it isn't, a
//  heuristic reasoner keeps the app fully functional offline.
//
//  Each `respond` call uses a fresh single-turn session, so there is no shared
//  mutable session state across concurrent calls (this removes the data race in
//  the previous multi-variant implementation). Conversation continuity is
//  achieved by passing prior turns in the prompt instead.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

protocol LanguageReasoner: Sendable {
    var isAvailable: Bool { get }
    var displayName: String { get }
    func respond(system: String?, prompt: String) async throws -> String
}

/// Fallback reasoner: no LLM. Agents detect `isAvailable == false` and use
/// their extractive / template branches instead of calling `respond`.
struct HeuristicReasoner: LanguageReasoner {
    var isAvailable: Bool { false }
    var displayName: String { "On-device (basic)" }
    func respond(system: String?, prompt: String) async throws -> String { "" }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
struct AppleIntelligenceReasoner: LanguageReasoner {
    private let model = SystemLanguageModel.default

    var isAvailable: Bool { model.isAvailable }
    var displayName: String { "Apple Intelligence" }

    func respond(system: String?, prompt: String) async throws -> String {
        guard model.isAvailable else {
            throw NSError(domain: "Compass", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence is unavailable."])
        }
        let session: LanguageModelSession
        if let system, !system.isEmpty {
            session = LanguageModelSession(model: model, instructions: { Instructions(system) })
        } else {
            session = LanguageModelSession(model: model)
        }
        let response = try await session.respond(to: Prompt(prompt))
        return response.content
    }
}
#endif

enum ReasonerFactory {
    static func make() -> LanguageReasoner {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let reasoner = AppleIntelligenceReasoner()
            if reasoner.isAvailable { return reasoner }
        }
        #endif
        return HeuristicReasoner()
    }
}
