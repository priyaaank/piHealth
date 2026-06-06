import SwiftUI

/// piHealth visual palette, derived from the product screenshots:
/// cream backgrounds, deep-green text, and a warm coral accent.
enum Theme {
    static let background = Color(hex: 0xFBF8F2)      // chat / page background
    static let card = Color(hex: 0xEFE6D6)            // beige info cards
    static let coral = Color(hex: 0xEE6A52)           // accent + macro card
    static let coralDeep = Color(hex: 0xE85C44)
    static let darkGreen = Color(hex: 0x1C3A31)       // primary text
    static let softText = Color(hex: 0x6E7D74)        // secondary text
    static let bubble = Color(hex: 0xF1EADE)          // assistant text bubbles
    static let flame = Color(hex: 0xF7A41D)           // streak flame

    static let title = Font.system(.title3, design: .rounded).weight(.semibold)
    static let body = Font.system(.body, design: .rounded)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
