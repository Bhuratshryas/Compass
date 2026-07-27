//
//  ImageHarness.swift
//  Compass image test harness (NOT part of the app target)
//
//  Generates 20 varied images, runs REAL Vision OCR on them (same request
//  configuration the app uses in ChatViewModel.extractText), then feeds the
//  extracted text through the Orchestrator's image path. This validates OCR
//  fidelity + image-answer synthesis + the "images never trigger web search"
//  and empty-question guards end-to-end.
//
//  Compile separately from Harness.swift (both define @main).
//

import Foundation
import AppKit
import Vision

// MARK: - Image generation

struct ImageSpec {
    let name: String
    let lines: [String]
    let question: String
    let fontName: String?      // nil = system font
    let fontSize: CGFloat
    let textColor: NSColor
    let background: NSColor
    let bold: Bool
}

func makeCGImage(_ spec: ImageSpec, size: NSSize = NSSize(width: 700, height: 460)) -> CGImage? {
    let image = NSImage(size: size)
    image.lockFocus()
    spec.background.setFill()
    NSRect(origin: .zero, size: size).fill()

    let style = NSMutableParagraphStyle()
    style.lineSpacing = 8
    style.lineBreakMode = .byWordWrapping

    let font: NSFont
    if let fontName = spec.fontName, let custom = NSFont(name: fontName, size: spec.fontSize) {
        font = custom
    } else if spec.bold {
        font = NSFont.boldSystemFont(ofSize: spec.fontSize)
    } else {
        font = NSFont.systemFont(ofSize: spec.fontSize)
    }

    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: spec.textColor,
        .paragraphStyle: style
    ]
    let text = spec.lines.joined(separator: "\n")
    text.draw(in: NSRect(x: 24, y: 24, width: size.width - 48, height: size.height - 48), withAttributes: attrs)
    image.unlockFocus()

    var rect = NSRect(origin: .zero, size: size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}

func savePNG(_ cg: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: cg)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - OCR (mirrors ChatViewModel.extractText)

func runOCR(_ cg: CGImage) -> String? {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    do {
        try handler.perform([request])
        let fragments = (request.results ?? []).compactMap { obs -> OCRTextBuilder.Fragment? in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            return OCRTextBuilder.Fragment(text: text, box: obs.boundingBox)
        }
        let assembled = OCRTextBuilder.assemble(fragments)
        return assembled.isEmpty ? nil : assembled
    } catch {
        return nil
    }
}

// MARK: - Specs (20 varied images)

func imageSpecs() -> [ImageSpec] {
    func s(_ name: String, _ lines: [String], q: String, font: String? = nil, size: CGFloat = 30,
           color: NSColor = .black, bg: NSColor = .white, bold: Bool = false) -> ImageSpec {
        ImageSpec(name: name, lines: lines, question: q, fontName: font, fontSize: size, textColor: color, background: bg, bold: bold)
    }
    return [
        s("meeting-notes", ["MEETING NOTES", "Ship v2 on Friday", "Owner: Priya", "Blocker: API keys"], q: "What does this say?"),
        s("receipt", ["Cafe Aroma", "Latte      $4.50", "Muffin     $3.25", "Subtotal   $7.75", "Tax        $0.68", "Total      $8.43"], q: "What is the total and how much was tax?", font: "Menlo", size: 26),
        s("stop-sign", ["STOP"], q: "", size: 90, color: .white, bg: .systemRed, bold: true),
        s("math", ["E = mc^2", "a^2 + b^2 = c^2"], q: "Explain the first equation.", size: 40),
        s("code", ["func add(a: Int, b: Int) -> Int {", "    return a + b", "}"], q: "What does this code do?", font: "Menlo", size: 24),
        s("quote", ["\"The only way to do great", "work is to love what you do.\"", "— Steve Jobs"], q: "Who said this?", size: 30),
        s("address", ["Jane Doe", "1600 Amphitheatre Pkwy", "Mountain View, CA 94043"], q: "Extract the ZIP code.", size: 28),
        s("phone", ["Call us:", "+1 (415) 555-0142"], q: "What is the phone number?", size: 34),
        s("wifi", ["WiFi: CompassGuest", "Password: Tr@vel2026!"], q: "What is the WiFi password?", font: "Menlo", size: 28),
        s("nutrition", ["Nutrition Facts", "Calories 240", "Total Fat 9g", "Sugars 12g", "Protein 5g"], q: "How many calories?", size: 26),
        s("error", ["Error 500", "Internal Server Error", "The request could not be completed."], q: "What kind of error is this?", size: 28),
        s("book", ["The Pragmatic Programmer", "by Andrew Hunt", "and David Thomas"], q: "Who are the authors?", size: 30),
        s("spanish", ["Bienvenidos a Madrid.", "La biblioteca abre a las nueve."], q: "What language is this and what does it mean?", size: 30),
        s("url", ["Visit", "https://compass.example.com/docs"], q: "What is the URL?", font: "Menlo", size: 30),
        s("table-numbers", ["Q1  120", "Q2  145", "Q3  160", "Q4  180"], q: "Which quarter had the highest value?", font: "Menlo", size: 30),
        s("blank", [""], q: "What does this say?"),
        s("low-contrast", ["Faint reminder:", "Pay rent by the 1st"], q: "What should I remember?", size: 30, color: NSColor(white: 0.72, alpha: 1), bg: .white),
        s("long-paragraph", [
            "Photosynthesis is the process by which green",
            "plants convert sunlight, water and carbon",
            "dioxide into glucose and oxygen. It occurs",
            "in the chloroplasts and is the basis of most",
            "food chains on Earth."
        ], q: "Summarize this in one sentence.", size: 26),
        s("handwriting-ish", ["Happy Birthday!", "See you at 7pm"], q: "What time should I arrive?", font: "Snell Roundhand", size: 40),
        s("mixed", ["Flight AA123", "Gate B7  Seat 14C", "Boards 6:45 PM"], q: "What is my gate and seat?", size: 28),
    ]
}

// MARK: - Main

@main
struct ImageHarness {
    static func main() async {
        let reasoner = ReasonerFactory.make()
        let orchestrator = Orchestrator(reasoner: reasoner)
        let provider = MockImageSearchProvider()
        let outDir = "/tmp/compass_images"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        print("================ COMPASS IMAGE / OCR TEST HARNESS ================")
        print("Active reasoner: \(reasoner.displayName) (isAvailable=\(reasoner.isAvailable))")
        print("Images saved to: \(outDir)")
        print("=================================================================\n")

        var issues: [String] = []
        let specs = imageSpecs()

        for (i, spec) in specs.enumerated() {
            let id = i + 1
            guard let cg = makeCGImage(spec) else {
                issues.append("[\(id)] failed to render image \(spec.name)")
                continue
            }
            let path = "\(outDir)/\(String(format: "%02d", id))_\(spec.name).png"
            savePNG(cg, to: path)

            let ocr = runOCR(cg)
            let config = OrchestrationConfig(webSearchEnabled: true, isOnline: true, provider: provider)
            let result = await orchestrator.answer(
                question: spec.question,
                conversationContext: nil,
                imageContext: ocr,
                imageAttached: true,
                config: config
            )

            print("── [\(id)] \(spec.name) ─────────────────────────────")
            print("   file: \(path)")
            print("   expected text: \(spec.lines.filter { !$0.isEmpty }.joined(separator: " ⏎ "))")
            print("   OCR read:      \(ocr ?? "(nothing)")")
            print("   Q: \(spec.question.isEmpty ? "(empty)" : spec.question)")
            print("   usedWebSearch=\(result.usedWebSearch)")
            print("   A: \(result.text)")
            print("")

            if result.usedWebSearch {
                issues.append("[\(id)] image question triggered web search")
            }
            if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("[\(id)] produced an EMPTY answer")
            }
        }

        print("===================== INVARIANT CHECK =====================")
        if issues.isEmpty {
            print("All automated invariants passed (\(specs.count) images).")
        } else {
            print("\(issues.count) issue(s):")
            for i in issues { print(" - \(i)") }
        }
    }
}

/// Unused for image questions (they never retrieve), but OrchestrationConfig
/// requires a provider.
struct MockImageSearchProvider: SearchProvider {
    let name = "none"
    func search(query: String, limit: Int) async throws -> [SearchCandidate] { [] }
}
