import SwiftUI

// MARK: - Jools Spacing

enum JoolsSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Jools Corner Radius

enum JoolsRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let full: CGFloat = 9999
}

// MARK: - Spacing View Modifiers

extension View {
    func joolsPadding(_ edges: Edge.Set = .all, _ size: CGFloat = JoolsSpacing.md) -> some View {
        self.padding(edges, size)
    }

    func joolsCornerRadius(_ radius: CGFloat = JoolsRadius.md) -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: radius))
    }
}
