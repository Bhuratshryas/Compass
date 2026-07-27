//
//  VerifierAgent.swift
//  Compass
//
//  Stage 6 (citation grounding / cleanup), plus a Reflexion-lite pass: keep
//  only the citations the answer actually uses, then renumber both the inline
//  markers and the source list so they stay consistent (e.g. if the model cited
//  [1] and [4], they become [1] and [2]). Prevents dangling or unsupported
//  citations from being shown to the user.
//

import Foundation

struct VerifiedAnswer {
    let text: String
    let sources: [WebSource]
}

struct VerifierAgent {
    func verify(text: String, sources: [WebSource]) -> VerifiedAnswer {
        guard !sources.isEmpty else { return VerifiedAnswer(text: text, sources: []) }

        // Which citation numbers appear in the answer?
        let used = citedNumbers(in: text)
        guard !used.isEmpty else {
            // The model didn't cite anything; keep sources as "references" but
            // don't fabricate inline markers.
            return VerifiedAnswer(text: text, sources: sources)
        }

        // Keep only used sources, in their original order, and renumber.
        let usedSourcesOrdered = sources.filter { used.contains($0.id) }
        var remap: [Int: Int] = [:]
        var renumbered: [WebSource] = []
        for (index, source) in usedSourcesOrdered.enumerated() {
            let newID = index + 1
            remap[source.id] = newID
            renumbered.append(WebSource(id: newID, title: source.title, url: source.url, snippet: source.snippet))
        }

        let rewritten = rewriteMarkers(in: text, remap: remap)
        return VerifiedAnswer(text: rewritten, sources: renumbered)
    }

    private func citedNumbers(in text: String) -> Set<Int> {
        var numbers = Set<Int>()
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d+)\]"#) else { return numbers }
        let range = NSRange(text.startIndex..., in: text)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let r = Range(match.range(at: 1), in: text), let n = Int(text[r]) else { return }
            numbers.insert(n)
        }
        return numbers
    }

    private func rewriteMarkers(in text: String, remap: [Int: Int]) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d+)\]"#) else { return text }
        let mutable = NSMutableString(string: text)
        let range = NSRange(location: 0, length: mutable.length)
        // Replace from the end to keep ranges valid as we mutate.
        var matches: [NSTextCheckingResult] = []
        regex.enumerateMatches(in: text, range: range) { m, _, _ in if let m { matches.append(m) } }
        for match in matches.reversed() {
            guard let numRange = Range(match.range(at: 1), in: text), let old = Int(text[numRange]) else { continue }
            if let new = remap[old] {
                mutable.replaceCharacters(in: match.range, with: "[\(new)]")
            } else {
                // Cited a source that got filtered out — drop the stray marker.
                mutable.replaceCharacters(in: match.range, with: "")
            }
        }
        return (mutable as String)
    }
}
