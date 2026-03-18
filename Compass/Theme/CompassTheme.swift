//
//  CompassTheme.swift
//  Compass
//

import SwiftUI

enum CompassTheme {
    // Brand: light brown / sand
    static let primary   = Color(hex: "8B5E3C")  // warm brown
    static let accent    = Color(hex: "C38E5C")  // lighter accent

    // Surfaces
    static let background = Color(hex: "F7F2EC") // soft sand
    static let surface    = Color(hex: "FFFFFF") // cards / bubbles
    static let separator  = Color(hex: "E3D7C9")

    // Text
    static let textPrimary   = Color(hex: "2B2118")
    static let textSecondary = Color(hex: "6A5A4A")
    static let textTertiary  = Color(hex: "A39383")
    static let textInverse   = Color.white

    // Chat bubbles
    static let userBubble      = Color(hex: "8B5E3C")
    static let assistantBubble = Color(hex: "F0E3D4")
    static let destructive     = Color(hex: "C0392B")

    // Layout
    static let cornerRadius: CGFloat = 12
    static let bubbleRadius: CGFloat = 18
    static let inputRadius: CGFloat = 22
    static let paddingH: CGFloat = 20
    static let paddingV: CGFloat = 12
    static let bubbleMaxWidth: CGFloat = 280
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
