//
//  RetrievalAgent.swift
//  Compass
//
//  Stages 2-3 of the pipeline (retrieval + ranking). Fans out the planned
//  sub-queries to the search provider in parallel, merges + dedupes candidates,
//  reranks them on-device, applies the quality gate, and (Perplexity-style
//  fail-safe) re-queries with a broadened query if too few candidates clear the
//  bar. Returns numbered `WebSource`s ready to ground synthesis.
//

import Foundation

struct RetrievalOutcome {
    let sources: [WebSource]
    /// Passages aligned to `sources` for the synthesis prompt.
    let evidence: [String]
}

struct RetrievalAgent {
    let provider: SearchProvider
    var reranker = Reranker()
    var maxSources = 4
    var candidatesPerQuery = 6

    func retrieve(plan: QueryPlan, originalQuery: String) async -> RetrievalOutcome {
        let queries = plan.subQueries.isEmpty ? [originalQuery] : plan.subQueries
        var candidates = await fanOut(queries: queries)

        var result = reranker.rank(query: originalQuery, subQueries: queries, candidates: candidates)

        // Fail-safe: broaden and re-query once instead of citing weak sources.
        if !result.passesQualityBar {
            let broadened = broaden(originalQuery)
            let extra = await fanOut(queries: [broadened])
            candidates = mergeUnique(candidates, extra)
            result = reranker.rank(query: originalQuery, subQueries: queries + [broadened], candidates: candidates)
        }

        let top = Array(result.ranked.prefix(maxSources))
        var sources: [WebSource] = []
        var evidence: [String] = []
        for (index, ranked) in top.enumerated() {
            let n = index + 1
            sources.append(
                WebSource(id: n,
                          title: cleanTitle(ranked.candidate.title, fallbackURL: ranked.candidate.url),
                          url: ranked.candidate.url,
                          snippet: ranked.candidate.snippet)
            )
            evidence.append("[\(n)] \(ranked.candidate.title): \(ranked.candidate.snippet)")
        }
        return RetrievalOutcome(sources: sources, evidence: evidence)
    }

    // MARK: - Fan-out

    private func fanOut(queries: [String]) async -> [SearchCandidate] {
        await withTaskGroup(of: [SearchCandidate].self) { group in
            for q in queries {
                group.addTask {
                    (try? await provider.search(query: q, limit: candidatesPerQuery)) ?? []
                }
            }
            var merged: [SearchCandidate] = []
            for await batch in group {
                merged = mergeUnique(merged, batch)
            }
            return merged
        }
    }

    private func mergeUnique(_ a: [SearchCandidate], _ b: [SearchCandidate]) -> [SearchCandidate] {
        var seen = Set(a.map { $0.url })
        var out = a
        for c in b where !seen.contains(c.url) {
            seen.insert(c.url)
            out.append(c)
        }
        return out
    }

    private func broaden(_ query: String) -> String {
        // Drop question words / punctuation to widen recall on the retry.
        let stripped = query
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: #"\b(what|who|when|where|why|which|how|is|are|the|a|an)\b"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        return stripped.trimmingCharacters(in: .whitespaces).isEmpty ? query : stripped.trimmingCharacters(in: .whitespaces)
    }

    private func cleanTitle(_ title: String, fallbackURL: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return URL(string: fallbackURL)?.host ?? "Source"
    }
}
