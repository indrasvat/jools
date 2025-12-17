import SwiftUI

// MARK: - Jools Color Palette

extension Color {
    // Primary accent colors (purple theme)
    static let joolsAccent = Color(hex: "8B5CF6")
    static let joolsAccentSecondary = Color(hex: "A855F7")
    static let joolsAccentDark = Color(hex: "7C3AED")
    static let joolsAccentLight = Color(hex: "C084FC")

    // Backgrounds
    static let joolsBackground = Color(uiColor: .systemBackground)
    static let joolsSurface = Color(uiColor: .secondarySystemBackground)
    static let joolsSurfaceElevated = Color(uiColor: .tertiarySystemBackground)

    // Chat bubbles
    static let joolsBubbleUser = Color(hex: "8B5CF6")
    static let joolsBubbleAgent = Color(uiColor: .tertiarySystemBackground)

    // Semantic colors
    static let joolsPlanBorder = Color.orange
    static let joolsSuccess = Color.green
    static let joolsError = Color.red
    static let joolsWarning = Color.yellow

    // State colors
    static let joolsRunning = Color.green
    static let joolsQueued = Color.blue
    static let joolsAwaiting = Color.orange
    static let joolsCompleted = Color(hex: "8B5CF6")
    static let joolsFailed = Color.red
    static let joolsCancelled = Color.gray
}

// MARK: - Gradients

extension LinearGradient {
    static let joolsAccentGradient = LinearGradient(
        colors: [Color(hex: "8B5CF6"), Color(hex: "A855F7"), Color(hex: "C084FC")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let joolsBackgroundGradient = LinearGradient(
        colors: [
            Color(hex: "8B5CF6").opacity(0.15),
            Color(hex: "A855F7").opacity(0.1),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Hex Color Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
