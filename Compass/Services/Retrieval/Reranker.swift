//
//  Reranker.swift
//  Compass
//
//  Perplexity-style multi-stage ranking, done entirely on-device:
//   - Lexical relevance via a compact BM25 scorer (keyword overlap).
//   - Semantic relevance via Apple's on-device NLEmbedding (dense cosine),
//     acting as a lightweight cross-encoder stand-in.
//  Scores are fused, normalized, and filtered by a quality threshold. If too
//  few candidates clear the bar, `passesQualityBar` reports false so the
//  RetrievalAgent can re-query rather than cite weak sources.
//

import Foundation
import NaturalLanguage

struct RankedCandidate: Equatable {
    let candidate: SearchCandidate
    let score: Double   // fused, normalized 0...1
}

struct RerankResult {
    let ranked: [RankedCandidate]
    /// True when at least `minPassRatio` of candidates clear `qualityThreshold`.
    let passesQualityBar: Bool
}

struct Reranker {
    /// L3-style quality gate. Perplexity uses ~0.7; we mirror that.
    var qualityThreshold: Double = 0.7
    /// If fewer than this fraction pass, discard and re-query.
    var minPassRatio: Double = 0.3
    /// Weight of semantic vs lexical signal in the fused score.
    var semanticWeight: Double = 0.6

    private let embedding = NLEmbedding.wordEmbedding(for: .english)

    /// Rank candidates against the (reformulated) query and its sub-queries.
    func rank(query: String, subQueries: [String], candidates: [SearchCandidate]) -> RerankResult {
        guard !candidates.isEmpty else { return RerankResult(ranked: [], passesQualityBar: false) }

        let deduped = dedupe(candidates)
        let queryTokens = tokenize(([query] + subQueries).joined(separator: " "))
        let queryVector = averagedVector(for: queryTokens)

        // Corpus stats for BM25 (over candidate snippets).
        let docs = deduped.map { tokenize("\($0.title) \($0.snippet)") }
        let avgLen = docs.isEmpty ? 1.0 : Double(docs.reduce(0) { $0 + $1.count }) / Double(docs.count)
        let df = documentFrequencies(docs)
        let n = Double(docs.count)

        var lexical: [Double] = []
        var semantic: [Double] = []
        for (index, tokens) in docs.enumerated() {
            lexical.append(bm25(queryTokens: queryTokens, docTokens: tokens, df: df, n: n, avgLen: avgLen))
            let docVector = averagedVector(for: tokens)
            semantic.append(cosine(queryVector, docVector).map { max(0, $0) } ?? 0)
            _ = index
        }

        let normLexical = normalize(lexical)
        let normSemantic = normalize(semantic)

        var ranked: [RankedCandidate] = []
        for i in 0..<deduped.count {
            let fused = semanticWeight * normSemantic[i] + (1 - semanticWeight) * normLexical[i]
            ranked.append(RankedCandidate(candidate: deduped[i], score: fused))
        }
        ranked.sort { $0.score > $1.score }

        let passing = ranked.filter { $0.score >= qualityThreshold }.count
        let passes = Double(passing) >= max(1, minPassRatio * Double(ranked.count))
        return RerankResult(ranked: ranked, passesQualityBar: passes)
    }

    // MARK: - Lexical (BM25)

    private func bm25(queryTokens: [String], docTokens: [String], df: [String: Int], n: Double, avgLen: Double) -> Double {
        guard !docTokens.isEmpty else { return 0 }
        let k1 = 1.5, b = 0.75
        let docLen = Double(docTokens.count)
        var tf: [String: Int] = [:]
        for t in docTokens { tf[t, default: 0] += 1 }

        var score = 0.0
        for term in Set(queryTokens) {
            guard let termFreq = tf[term] else { continue }
            let docFreq = Double(df[term] ?? 0)
            let idf = log(1 + (n - docFreq + 0.5) / (docFreq + 0.5))
            let numerator = Double(termFreq) * (k1 + 1)
            let denominator = Double(termFreq) + k1 * (1 - b + b * docLen / avgLen)
            score += idf * numerator / denominator
        }
        return score
    }

    private func documentFrequencies(_ docs: [[String]]) -> [String: Int] {
        var df: [String: Int] = [:]
        for tokens in docs {
            for term in Set(tokens) { df[term, default: 0] += 1 }
        }
        return df
    }

    // MARK: - Semantic (NLEmbedding)

    private func averagedVector(for tokens: [String]) -> [Double]? {
        guard let embedding else { return nil }
        var sum: [Double]? = nil
        var count = 0
        for token in tokens {
            guard let vec = embedding.vector(for: token) else { continue }
            if sum == nil { sum = [Double](repeating: 0, count: vec.count) }
            guard var s = sum, s.count == vec.count else { continue }
            for i in 0..<vec.count { s[i] += vec[i] }
            sum = s
            count += 1
        }
        guard var result = sum, count > 0 else { return nil }
        for i in 0..<result.count { result[i] /= Double(count) }
        return result
    }

    private func cosine(_ a: [Double]?, _ b: [Double]?) -> Double? {
        guard let a, let b, a.count == b.count, !a.isEmpty else { return nil }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return nil }
        return dot / (sqrt(na) * sqrt(nb))
    }

    // MARK: - Helpers

    private func normalize(_ values: [Double]) -> [Double] {
        guard let maxV = values.max(), let minV = values.min(), maxV > minV else {
            return values.map { _ in values.isEmpty ? 0 : 1 }
        }
        return values.map { ($0 - minV) / (maxV - minV) }
    }

    private func dedupe(_ candidates: [SearchCandidate]) -> [SearchCandidate] {
        var seenURLs = Set<String>()
        var seenSnippets = Set<String>()
        var out: [SearchCandidate] = []
        for c in candidates {
            let urlKey = URL(string: c.url)?.absoluteString ?? c.url
            let snippetKey = c.snippet.lowercased().prefix(120)
            if seenURLs.contains(urlKey) || seenSnippets.contains(String(snippetKey)) { continue }
            seenURLs.insert(urlKey)
            seenSnippets.insert(String(snippetKey))
            out.append(c)
        }
        return out
    }

    private func tokenize(_ text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var tokens: [String] = []
        let stopwords: Set<String> = ["the", "a", "an", "of", "to", "in", "on", "for", "and", "or", "is", "are", "was", "were", "be", "with", "at", "by", "it", "this", "that", "as", "from", "what", "which", "who", "how"]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace, .omitOther]) { _, range in
            let token = text[range].lowercased()
            if token.count > 1 && !stopwords.contains(token) {
                tokens.append(token)
            }
            return true
        }
        return tokens
    }
}
