import SwiftUI

// MARK: - Jools Typography

extension Font {
    // Titles
    static let joolsLargeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let joolsTitle = Font.system(.title, design: .rounded).weight(.semibold)
    static let joolsTitle2 = Font.system(.title2, design: .rounded).weight(.semibold)
    static let joolsTitle3 = Font.system(.title3, design: .rounded).weight(.medium)

    // Body text
    static let joolsHeadline = Font.system(.headline, design: .default)
    static let joolsBody = Font.system(.body, design: .default)
    static let joolsCallout = Font.system(.callout, design: .default)
    static let joolsSubheadline = Font.system(.subheadline, design: .default)
    static let joolsFootnote = Font.system(.footnote, design: .default)
    static let joolsCaption = Font.system(.caption, design: .default)
    static let joolsCaption2 = Font.system(.caption2, design: .default)

    // Code
    static let joolsCode = Font.system(.body, design: .monospaced)
    static let joolsCodeSmall = Font.system(.footnote, design: .monospaced)
}

// MARK: - Text Style Modifiers

extension View {
    func joolsLargeTitle() -> some View {
        self.font(.joolsLargeTitle)
    }

    func joolsTitle() -> some View {
        self.font(.joolsTitle)
    }

    func joolsHeadline() -> some View {
        self.font(.joolsHeadline)
    }

    func joolsBody() -> some View {
        self.font(.joolsBody)
    }

    func joolsCaption() -> some View {
        self.font(.joolsCaption)
            .foregroundStyle(.secondary)
    }

    func joolsCode() -> some View {
        self.font(.joolsCode)
    }
}
