//
//  SearchProvider.swift
//  Compass
//
//  Pluggable web-search backend. The RetrievalAgent depends only on this
//  protocol, so providers (DuckDuckGo, Brave, a mock, …) are interchangeable.
//

import Foundation

/// A raw candidate returned by a search backend, before ranking.
struct SearchCandidate: Equatable, Hashable {
    let title: String
    let url: String
    let snippet: String
}

protocol SearchProvider: Sendable {
    /// Human-readable provider name (for diagnostics / disclosure).
    var name: String { get }
    /// Run a single query and return raw candidates. Should throw on transport
    /// errors so the caller can decide how to degrade.
    func search(query: String, limit: Int) async throws -> [SearchCandidate]
}

enum SearchProviderError: Error {
    case badResponse
    case notConfigured
}

/// Chooses the best available provider given current settings.
enum SearchProviderFactory {
    @MainActor
    static func make() -> SearchProvider {
        let key = AppSettings.shared.braveAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            return BraveSearchProvider(apiKey: key)
        }
        return DuckDuckGoSearchProvider()
    }
}
