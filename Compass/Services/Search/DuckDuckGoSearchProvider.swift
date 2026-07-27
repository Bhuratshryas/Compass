//
//  DuckDuckGoSearchProvider.swift
//  Compass
//
//  Keyless default provider using DuckDuckGo's Instant Answer API. It returns
//  structured JSON (no HTML scraping) and requires no API key, which keeps the
//  app usable out of the box. Coverage is shallower than a full web-search API;
//  set a Brave API key in Settings for richer results.
//

import Foundation

struct DuckDuckGoSearchProvider: SearchProvider {
    let name = "DuckDuckGo"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String, limit: Int) async throws -> [SearchCandidate] {
        var components = URLComponents(string: "https://api.duckduckgo.com/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "no_redirect", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1")
        ]
        guard let url = components.url else { throw SearchProviderError.badResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Compass-LocalAI/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SearchProviderError.badResponse
        }

        let decoded = try JSONDecoder().decode(DDGResponse.self, from: data)
        var candidates: [SearchCandidate] = []

        // The primary abstract, when present, is usually the strongest source.
        if let abstract = decoded.abstractText, !abstract.isEmpty,
           let source = decoded.abstractURL, !source.isEmpty {
            candidates.append(
                SearchCandidate(
                    title: decoded.heading ?? URL(string: source)?.host ?? "Source",
                    url: source,
                    snippet: abstract
                )
            )
        }

        // Related topics (flattened, since some entries are nested groups).
        for topic in decoded.relatedTopics {
            appendTopic(topic, into: &candidates)
            if candidates.count >= limit { break }
        }

        return Array(candidates.prefix(limit))
    }

    private func appendTopic(_ topic: DDGResponse.RelatedTopic, into candidates: inout [SearchCandidate]) {
        if let text = topic.text, let url = topic.firstURL, !text.isEmpty, !url.isEmpty {
            let title = text.split(separator: "-", maxSplits: 1).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? text
            candidates.append(SearchCandidate(title: title, url: url, snippet: text))
        }
        if let nested = topic.topics {
            for sub in nested {
                appendTopic(sub, into: &candidates)
            }
        }
    }

    private struct DDGResponse: Decodable {
        let abstractText: String?
        let abstractURL: String?
        let heading: String?
        let relatedTopics: [RelatedTopic]

        enum CodingKeys: String, CodingKey {
            case abstractText = "AbstractText"
            case abstractURL = "AbstractURL"
            case heading = "Heading"
            case relatedTopics = "RelatedTopics"
        }

        struct RelatedTopic: Decodable {
            let text: String?
            let firstURL: String?
            let topics: [RelatedTopic]?

            enum CodingKeys: String, CodingKey {
                case text = "Text"
                case firstURL = "FirstURL"
                case topics = "Topics"
            }
        }
    }
}
