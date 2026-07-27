//
//  BraveSearchProvider.swift
//  Compass
//
//  Higher-quality provider used when the user supplies a Brave Search API key
//  in Settings. Brave is privacy-respecting and returns full web results with
//  titles, URLs and descriptions — ideal for citation-grounded answers.
//

import Foundation

struct BraveSearchProvider: SearchProvider {
    let name = "Brave"

    let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func search(query: String, limit: Int) async throws -> [SearchCandidate] {
        guard !apiKey.isEmpty else { throw SearchProviderError.notConfigured }

        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(max(1, min(limit, 20)))),
            URLQueryItem(name: "safesearch", value: "moderate")
        ]
        guard let url = components.url else { throw SearchProviderError.badResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SearchProviderError.badResponse
        }

        let decoded = try JSONDecoder().decode(BraveResponse.self, from: data)
        let results = decoded.web?.results ?? []
        return results.prefix(limit).map {
            SearchCandidate(title: $0.title, url: $0.url, snippet: $0.description ?? "")
        }
    }

    private struct BraveResponse: Decodable {
        let web: Web?
        struct Web: Decodable { let results: [Result] }
        struct Result: Decodable {
            let title: String
            let url: String
            let description: String?
        }
    }
}
