import SwiftUI
import UIKit
import ReadingListCore

// MARK: - Colours
//
// The palette follows the web app's design tokens (assets/styles.css) so the two look
// like the same product. Status colours are the only semantic colours the app has:
// grey not started, blue in progress, green finished. Everything else is system.

enum AppColor {
    static let accent = Color.accentColor
    static let yellow = Color(light: Color(hex: 0xF2B705), dark: Color(hex: 0xFFC93C))
    static let blue = Color(light: Color(hex: 0x2F6FD0), dark: Color(hex: 0x6EA8FE))
    static let green = Color(light: Color(hex: 0x1F8A54), dark: Color(hex: 0x4ADE80))

    static func status(_ status: ReadStatus) -> Color {
        switch status {
        case .unread: return Color.secondary.opacity(0.45)
        case .reading: return blue
        case .finished: return green
        }
    }

    /// Cover placeholder colour keyed to the series name, same hash as the web app,
    /// so "Fantastic Four" is the same hue on every device.
    static func series(_ name: String) -> Color {
        var h = 0
        for scalar in name.unicodeScalars { h = (h * 31 + Int(scalar.value)) % 360 }
        return Color(hue: Double(h) / 360, saturation: 0.55, brightness: 0.62)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// A colour that adapts to the current appearance.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

// MARK: - Text helpers

enum SeriesInitials {
    private static let joiners: Set<String> = ["the", "of", "and", "a", "an", "in", "to", "vs", "at", "for"]

    /// "Books of Doom" → "BD", "Watchmen" → "WA". Used on cover placeholders.
    static func of(_ name: String) -> String {
        let cleaned = name.map { $0.isLetter || $0.isNumber || $0 == " " ? $0 : " " }
        let words = String(cleaned).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        var significant = words.filter { !joiners.contains($0.lowercased()) }
        if significant.isEmpty { significant = words }
        guard let first = significant.first else { return "?" }
        if significant.count > 1, let second = significant.dropFirst().first?.first {
            return String([first.first!, second]).uppercased()
        }
        return String(first.prefix(2)).uppercased()
    }
}

enum Plural {
    static func count(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        "\(n) \(n == 1 ? one : (many ?? one + "s"))"
    }
}

// MARK: - Haptics

enum Haptics {
    static func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Layout constants

enum Metrics {
    static let coverRadius: CGFloat = 8
    static let coverAspect: CGFloat = 2.0 / 3.0   // portrait comic cover
    static let rowCoverWidth: CGFloat = 52
    static let gridMinimum: CGFloat = 120
}
