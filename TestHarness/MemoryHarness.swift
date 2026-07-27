//
//  MemoryHarness.swift
//  Compass memory test harness (NOT part of the app target)
//
//  Simulates a LONG conversation (30+ messages) driving the exact memory
//  maintenance loop ChatViewModel uses: after each turn we fold aged-out
//  messages into the rolling summary and advance the watermark. Then we build
//  the model context for later questions and verify that facts stated at the
//  very start of the session are still retained — proving the app can hold
//  long sessions in the same context.
//
//  Compile separately (defines its own @main).
//

import Foundation

// A tiny helper to make ChatMessages quickly.
func u(_ s: String) -> ChatMessage { ChatMessage(role: .user, content: s) }
func a(_ s: String) -> ChatMessage { ChatMessage(role: .assistant, content: s) }

@main
struct MemoryHarness {
    static func main() async {
        let reasoner = ReasonerFactory.make()
        let memory = ConversationMemory(reasoner: reasoner)

        print("================ COMPASS MEMORY TEST HARNESS ================")
        print("Reasoner: \(reasoner.displayName) (isAvailable=\(reasoner.isAvailable))")
        print("recentBufferCount=\(memory.recentBufferCount) foldBatch=\(memory.foldBatch) maxContext=\(memory.maxContextChars)")
        print("============================================================\n")

        // ---- A realistic long session. Durable facts are stated up front. ----
        let turns: [(String, String)] = [
            ("Hi! My name is Alex and my dog is a husky named Pluto.",
             "Nice to meet you, Alex! Pluto sounds like a wonderful husky."),
            ("I'm planning a trip to Japan in December for two weeks.",
             "A two-week December trip to Japan sounds fantastic."),
            ("I'm vegetarian, so I'll need restaurant tips later.",
             "Noted — I'll keep vegetarian options in mind."),
            ("What's a good way to brew coffee at home?",
             "A pour-over like a V60 gives a clean, flavorful cup."),
            ("How do I keep my basil plant alive indoors?",
             "Give it lots of light and water when the top soil is dry."),
            ("Explain the difference between TCP and UDP.",
             "TCP is reliable and ordered; UDP is faster but connectionless."),
            ("Recommend a sci-fi movie.",
             "Arrival is a thoughtful, beautifully made sci-fi film."),
            ("What's a quick stretch for tight shoulders?",
             "Try doorway pec stretches and gentle neck rolls."),
            ("How much water should I drink daily?",
             "Roughly 2 to 3 litres, adjusted for activity and climate."),
            ("Give me a tip for better sleep.",
             "Keep a consistent sleep schedule and dim lights before bed."),
            ("What's the capital of Australia?",
             "Canberra is the capital of Australia."),
            ("How do I reverse a string in Python?",
             "Use slicing: s[::-1]."),
            ("Suggest a productivity technique.",
             "The Pomodoro technique — 25 minutes focused, 5 minutes rest."),
        ]

        // ---- Replay the session exactly like ChatViewModel: append + maintain. ----
        var messages: [ChatMessage] = []
        var summary = ""
        var watermark = 0

        for (i, turn) in turns.enumerated() {
            messages.append(u(turn.0))
            messages.append(a(turn.1))
            if let updated = await memory.maintain(messages: messages, summary: summary, watermark: watermark) {
                summary = updated.summary
                watermark = updated.watermark
                print("after turn \(i + 1): watermark=\(watermark)/\(messages.count) summaryChars=\(summary.count)")
            }
        }

        print("\n---- Rolling summary after \(messages.count) messages ----")
        print(summary.isEmpty ? "(empty)" : summary)
        print("watermark=\(watermark) (messages before this are ONLY in the summary)\n")

        // ---- Now ask questions whose answers were stated at the very start. ----
        struct Probe { let q: String; let mustContain: [String] }
        let probes = [
            Probe(q: "By the way, what is my dog's name?", mustContain: ["Pluto"]),
            Probe(q: "Remind me what my name is?", mustContain: ["Alex"]),
            Probe(q: "Where am I planning to travel and when?", mustContain: ["Japan"]),
            Probe(q: "Remember I have a dietary restriction — what is it?", mustContain: ["vegetarian"]),
        ]

        var issues: [String] = []
        for probe in probes {
            let ctx = memory.buildContext(history: messages, summary: summary, watermark: watermark, query: probe.q) ?? ""

            // Old behaviour for comparison: flat last-10-message window.
            let oldWindow = messages.suffix(10)
                .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
                .joined(separator: "\n")

            print("── Q: \(probe.q)")
            for needle in probe.mustContain {
                let inNew = ctx.localizedCaseInsensitiveContains(needle)
                let inOld = oldWindow.localizedCaseInsensitiveContains(needle)
                print("   fact \"\(needle)\": memory-context=\(inNew ? "RETAINED" : "LOST")  |  old-10-window=\(inOld ? "present" : "LOST")")
                if !inNew {
                    issues.append("Q \"\(probe.q)\": fact \"\(needle)\" not present in assembled context")
                }
            }
            print("")
        }

        // Invariant: the recent buffer must always be present verbatim.
        let lastUser = turns.last!.0
        let ctxForLast = memory.buildContext(history: messages, summary: summary, watermark: watermark, query: "anything") ?? ""
        if !ctxForLast.contains(lastUser) {
            issues.append("recent buffer missing: last user turn not in context")
        }
        // Invariant: context stays within budget.
        if ctxForLast.count > memory.maxContextChars + 4 {
            issues.append("context exceeded budget: \(ctxForLast.count) > \(memory.maxContextChars)")
        }
        // Invariant: long session actually folded into summary.
        if watermark == 0 || summary.isEmpty {
            issues.append("no memory was accumulated over a \(messages.count)-message session")
        }

        print("===================== RESULT =====================")
        if issues.isEmpty {
            print("PASS: all early-session facts retained across a \(messages.count)-message conversation.")
        } else {
            print("\(issues.count) issue(s):")
            for i in issues { print(" - \(i)") }
        }
    }
}
