//
//  OCRTextBuilder.swift
//  Compass
//
//  Reconstructs readable text from Vision OCR fragments while preserving the
//  visual layout. Vision returns recognized regions that can be ordered
//  column-first (e.g. all labels, then all prices on a receipt); joining them
//  with spaces destroys row/column pairing and leads to wrong answers. This
//  groups fragments into visual rows by vertical position, orders each row
//  left-to-right, and joins rows with newlines so tables, receipts, and forms
//  keep their structure.
//
//  Fragment boxes use Vision's normalized coordinate space (origin bottom-left,
//  y increasing upward), matching VNRecognizedTextObservation.boundingBox.
//

import Foundation
import CoreGraphics

enum OCRTextBuilder {
    struct Fragment {
        let text: String
        let box: CGRect
    }

    static func assemble(_ fragments: [Fragment]) -> String {
        let clean = fragments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !clean.isEmpty else { return "" }

        // Top-to-bottom (higher midY is higher on the page in Vision space).
        let sorted = clean.sorted { $0.box.midY > $1.box.midY }

        var lines: [[Fragment]] = []
        for frag in sorted {
            if let last = lines.last {
                let lineMidY = last.map { $0.box.midY }.reduce(0, +) / CGFloat(last.count)
                let lineHeight = last.map { $0.box.height }.max() ?? frag.box.height
                let tolerance = max(lineHeight, frag.box.height) * 0.6
                if abs(frag.box.midY - lineMidY) <= tolerance {
                    lines[lines.count - 1].append(frag)
                    continue
                }
            }
            lines.append([frag])
        }

        let rows = lines.map { row -> String in
            row.sorted { $0.box.minX < $1.box.minX }
               .map { $0.text.trimmingCharacters(in: .whitespaces) }
               .joined(separator: "  ")
        }
        return rows.joined(separator: "\n")
    }
}
