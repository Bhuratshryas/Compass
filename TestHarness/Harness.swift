//
//  Harness.swift
//  Compass test harness (NOT part of the app target)
//
//  Drives the real orchestration pipeline (QueryPlanner → RetrievalAgent →
//  Reranker → SynthesisAgent → VerifierAgent → Orchestrator) through 50
//  scenarios covering new chats, continuous conversations, online/offline,
//  web-search on/off, and image (OCR) context. Uses a deterministic mock
//  search provider so citations and grounding are verifiable.
//
//  Compile: see run_harness.sh
//

import Foundation

// MARK: - Mock search provider with a small deterministic knowledge base.

struct MockSearchProvider: SearchProvider {
    let name = "MockSearch"

    private static let kb: [(keys: [String], candidate: SearchCandidate)] = [
        (["capital of france", "paris"],
         SearchCandidate(title: "Paris - Wikipedia", url: "https://en.wikipedia.org/wiki/Paris",
                         snippet: "Paris is the capital and most populous city of France, with an estimated population of over 2 million residents.")),
        (["ceo of apple", "apple ceo", "tim cook"],
         SearchCandidate(title: "Tim Cook - Apple Leadership", url: "https://www.apple.com/leadership/tim-cook/",
                         snippet: "Tim Cook is the chief executive officer of Apple and serves on its board of directors.")),
        (["latest iphone", "newest iphone", "iphone 17", "iphone"],
         SearchCandidate(title: "iPhone - Apple", url: "https://www.apple.com/iphone/",
                         snippet: "The latest iPhone lineup features the A-series chip, an advanced camera system, and iOS with Apple Intelligence.")),
        (["height of mount everest", "mount everest", "everest"],
         SearchCandidate(title: "Mount Everest - Wikipedia", url: "https://en.wikipedia.org/wiki/Mount_Everest",
                         snippet: "Mount Everest is Earth's highest mountain above sea level, with a peak at 8,849 metres (29,032 ft).")),
        (["speed of light"],
         SearchCandidate(title: "Speed of light - Wikipedia", url: "https://en.wikipedia.org/wiki/Speed_of_light",
                         snippet: "The speed of light in vacuum is exactly 299,792,458 metres per second.")),
        (["who wrote romeo and juliet", "romeo and juliet", "shakespeare"],
         SearchCandidate(title: "Romeo and Juliet - Wikipedia", url: "https://en.wikipedia.org/wiki/Romeo_and_Juliet",
                         snippet: "Romeo and Juliet is a tragedy written by William Shakespeare early in his career.")),
        (["when did shakespeare die", "shakespeare death", "shakespeare die", "shakespeare"],
         SearchCandidate(title: "William Shakespeare - Wikipedia", url: "https://en.wikipedia.org/wiki/William_Shakespeare",
                         snippet: "William Shakespeare died on 23 April 1616 in Stratford-upon-Avon, at the age of 52. He also wrote Hamlet, Macbeth and Othello.")),
        (["world cup 2022", "fifa world cup 2022"],
         SearchCandidate(title: "2022 FIFA World Cup - Wikipedia", url: "https://en.wikipedia.org/wiki/2022_FIFA_World_Cup",
                         snippet: "Argentina won the 2022 FIFA World Cup, defeating France on penalties in the final held in Qatar.")),
        (["python programming", "python language"],
         SearchCandidate(title: "Python (programming language)", url: "https://en.wikipedia.org/wiki/Python_(programming_language)",
                         snippet: "Python is a high-level, general-purpose programming language known for readable syntax and a large standard library.")),
        (["tallest building", "burj khalifa"],
         SearchCandidate(title: "Burj Khalifa - Wikipedia", url: "https://en.wikipedia.org/wiki/Burj_Khalifa",
                         snippet: "The Burj Khalifa in Dubai is the world's tallest building, standing 828 metres (2,717 ft) tall.")),
        (["population of tokyo", "tokyo population"],
         SearchCandidate(title: "Tokyo - Wikipedia", url: "https://en.wikipedia.org/wiki/Tokyo",
                         snippet: "Tokyo is the capital of Japan and the most populous metropolitan area in the world, with about 37 million people.")),
        (["bitcoin price", "price of bitcoin"],
         SearchCandidate(title: "Bitcoin price - CoinDesk", url: "https://www.coindesk.com/price/bitcoin/",
                         snippet: "Bitcoin's price fluctuates continuously on global exchanges; check a live source for the current value.")),
    ]

    func search(query: String, limit: Int) async throws -> [SearchCandidate] {
        let q = query.lowercased()
        var out: [SearchCandidate] = []
        for entry in Self.kb where entry.keys.contains(where: { q.contains($0) }) {
            out.append(entry.candidate)
        }
        // Add a couple of generic near-duplicates for some queries so the
        // reranker and dedup logic have something to chew on.
        if out.isEmpty, q.contains("everest") {
            out.append(Self.kb.first(where: { $0.keys.contains("everest") })!.candidate)
        }
        return Array(out.prefix(limit))
    }
}

// MARK: - Scenario model

struct Scenario {
    let id: Int
    let label: String
    let question: String
    let online: Bool
    let webEnabled: Bool
    let imageContext: String?
    /// Prior turns as (user, assistant) pairs, used to build conversation context.
    let priorTurns: [(String, String)]
}

// MARK: - Helpers

func conversationContext(from turns: [(String, String)]) -> String? {
    guard !turns.isEmpty else { return nil }
    let limited = turns.suffix(5)
    let lines = limited.flatMap { ["User: \($0.0)", "Assistant: \($0.1)"] }
    return lines.joined(separator: "\n")
}

func citationNumbers(in text: String) -> [Int] {
    guard let regex = try? NSRegularExpression(pattern: #"\[(\d+)\]"#) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    var nums: [Int] = []
    regex.enumerateMatches(in: text, range: range) { m, _, _ in
        if let m, let r = Range(m.range(at: 1), in: text), let n = Int(text[r]) { nums.append(n) }
    }
    return nums
}

// MARK: - Main

@main
struct Harness {
    static func main() async {
        let reasoner = ReasonerFactory.make()
        let orchestrator = Orchestrator(reasoner: reasoner)
        let provider = MockSearchProvider()

        print("================ COMPASS ORCHESTRATION TEST HARNESS ================")
        print("Active reasoner: \(reasoner.displayName) (isAvailable=\(reasoner.isAvailable))")
        print("Search provider: \(provider.name)")
        print("===================================================================\n")

        let scenarios = buildScenarios()
        var issues: [String] = []

        for s in scenarios {
            let ctx = conversationContext(from: s.priorTurns)
            let config = OrchestrationConfig(webSearchEnabled: s.webEnabled, isOnline: s.online, provider: provider)
            let result = await orchestrator.answer(
                question: s.question,
                conversationContext: ctx,
                imageContext: s.imageContext,
                config: config
            )

            print("── [\(s.id)] \(s.label) ─────────────────────────────")
            if !s.priorTurns.isEmpty {
                print("   context: \(s.priorTurns.map { $0.0 }.joined(separator: " | "))")
            }
            print("   Q: \(s.question)")
            print("   flags: online=\(s.online) web=\(s.webEnabled)\(s.imageContext != nil ? " image=yes" : "")")
            print("   usedWebSearch=\(result.usedWebSearch)  sources=\(result.sources.count)")
            print("   A: \(result.text)")
            if !result.sources.isEmpty {
                for src in result.sources { print("      [\(src.id)] \(src.title) — \(src.host)") }
            }

            // Automated invariant checks.
            let cited = Set(citationNumbers(in: result.text))
            let available = Set(result.sources.map { $0.id })
            if !cited.isSubset(of: available) {
                issues.append("[\(s.id)] cites \(cited.sorted()) but sources are \(available.sorted()) (dangling citation)")
            }
            if result.usedWebSearch && result.sources.isEmpty {
                issues.append("[\(s.id)] usedWebSearch=true but no sources")
            }
            if !s.online && result.usedWebSearch {
                issues.append("[\(s.id)] performed web search while OFFLINE")
            }
            if !s.webEnabled && result.usedWebSearch {
                issues.append("[\(s.id)] performed web search while web DISABLED")
            }
            if s.imageContext != nil && result.usedWebSearch {
                issues.append("[\(s.id)] performed web search for an image question")
            }
            if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("[\(s.id)] produced an EMPTY answer")
            }
            print("")
        }

        print("===================== INVARIANT CHECK =====================")
        if issues.isEmpty {
            print("All automated invariants passed (\(scenarios.count) scenarios).")
        } else {
            print("\(issues.count) issue(s):")
            for i in issues { print(" - \(i)") }
        }
    }

    static func buildScenarios() -> [Scenario] {
        var s: [Scenario] = []
        func add(_ label: String, _ q: String, online: Bool = true, web: Bool = true, image: String? = nil, prior: [(String, String)] = []) {
            s.append(Scenario(id: s.count + 1, label: label, question: q, online: online, webEnabled: web, imageContext: image, priorTurns: prior))
        }

        // --- New chats: conversational (should NOT retrieve) ---
        add("new/conversational", "hello")
        add("new/conversational", "hi there")
        add("new/conversational", "thanks!")
        add("new/conversational", "how are you")

        // --- New chats: factual, web ON + online (should retrieve + cite) ---
        add("new/factual-web", "What is the capital of France?")
        add("new/factual-web", "Who is the CEO of Apple?")
        add("new/factual-web", "What is the height of Mount Everest?")
        add("new/factual-web", "Who wrote Romeo and Juliet?")
        add("new/factual-web", "What is the population of Tokyo?")
        add("new/factual-web", "What is the tallest building in the world?")
        add("new/factual-web", "Who won the World Cup 2022?")

        // --- Freshness cues (should retrieve) ---
        add("new/fresh", "What is the latest iPhone?")
        add("new/fresh", "What is the current price of Bitcoin?")
        add("new/fresh", "What's the weather today?")

        // --- Factual but general knowledge, no proper noun (routing = local) ---
        add("new/general", "Explain photosynthesis")
        add("new/general", "What is the speed of light?")
        add("new/general", "How does a rainbow form?")
        add("new/general", "What is 2 + 2?")
        add("new/general", "Tell me about the Eiffel Tower")

        // --- Web enabled but OFFLINE (must fall back to on-device) ---
        add("offline", "What is the capital of France?", online: false)
        add("offline", "Who is the CEO of Apple?", online: false)
        add("offline", "What is the latest iPhone?", online: false)

        // --- Web DISABLED (must stay on-device even though online) ---
        add("web-off", "What is the capital of France?", web: false)
        add("web-off", "Who won the World Cup 2022?", web: false)
        add("web-off", "What is the current price of Bitcoin?", web: false)

        // --- Image (OCR) context (must not retrieve) ---
        add("image", "What does this say?", image: "MEETING NOTES: Ship v2 on Friday. Owner: Priya.")
        add("image", "", image: "Total: $42.50  Tax: $3.10  Thank you!")
        add("image", "Summarize this", image: "The quarterly revenue grew 12% to $4.2M, driven by subscriptions.")

        // --- Multi-part questions ---
        add("multi-part", "What is the capital of France and who is the CEO of Apple?")
        add("multi-part", "Explain photosynthesis and how a rainbow forms")

        // --- Edge cases ---
        add("edge/empty", "")
        add("edge/gibberish", "asdklfj qweoiru")
        add("edge/very-short", "Everest")
        add("edge/punct", "???")

        // --- Continuous conversation A: Shakespeare (pronoun follow-up) ---
        let convA1: [(String, String)] = [("Who wrote Romeo and Juliet?", "William Shakespeare wrote Romeo and Juliet [1].")]
        add("continued/A2-pronoun", "When did he die?", prior: convA1)
        let convA2 = convA1 + [("When did he die?", "He died on 23 April 1616 [1].")]
        add("continued/A3-followup", "What else did he write?", prior: convA2)

        // --- Continuous conversation B: Apple ---
        let convB1: [(String, String)] = [("Who is the CEO of Apple?", "Tim Cook is the CEO of Apple [1].")]
        add("continued/B2", "What is their latest iPhone?", prior: convB1)
        let convB2 = convB1 + [("What is their latest iPhone?", "The latest iPhone features the newest A-series chip [1].")]
        add("continued/B3-conversational", "thanks!", prior: convB2)

        // --- Continuous conversation C: general knowledge thread (no retrieval) ---
        let convC1: [(String, String)] = [("Explain photosynthesis", "Photosynthesis is how plants convert light into energy.")]
        add("continued/C2", "Can you give an example?", prior: convC1)
        add("continued/C3", "Why is it important?", prior: convC1)

        // --- Continuous conversation D: offline thread ---
        let convD1: [(String, String)] = [("What is the capital of France?", "Paris is the capital of France.")]
        add("continued/D2-offline", "How many people live there?", online: false, prior: convD1)

        // --- Continuous conversation E: Everest thread with follow-up ---
        let convE1: [(String, String)] = [("What is the height of Mount Everest?", "Mount Everest is 8,849 m tall [1].")]
        add("continued/E2", "Where is it located?", prior: convE1)

        // --- More new factual to reach 50 ---
        add("new/factual-web", "What is Python programming?")
        add("new/factual-web", "How tall is the Burj Khalifa?")
        add("new/fresh", "Any recent news about the iPhone?")
        add("new/general", "Define entropy")
        add("new/general", "What is the meaning of life?")
        add("web-off", "What is the population of Tokyo?", web: false)
        add("offline", "Who wrote Romeo and Juliet?", online: false)
        add("new/factual-web", "Where is Mount Everest?")

        return s
    }
}
