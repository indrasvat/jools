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

/// Footer tagline shown in scrollable lists.
///
/// Worded so it actually makes sense for a third-party client: Jools is
/// built by a human for Jules users, so the credit goes to the author.
/// The `indrasvat` handle is painted with the brand accent gradient so
/// it reads as a signature in the app's theme colours, not a product
/// name.
struct MadeWithJoolsFooter: View {
    enum Style {
        case scroll
        case list
    }

    var style: Style = .scroll

    var body: some View {
        HStack(spacing: JoolsSpacing.xs) {
            Text("Made with")
                .font(.joolsCaption)
                .foregroundStyle(.secondary)

            Image(systemName: "heart.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(LinearGradient.joolsAccentGradient)
                .accessibilityLabel("love")

            Text("by")
                .font(.joolsCaption)
                .foregroundStyle(.secondary)

            Text("indrasvat")
                .font(.joolsCaption.weight(.semibold))
                .foregroundStyle(LinearGradient.joolsAccentGradient)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, style == .scroll ? JoolsSpacing.xl : JoolsSpacing.md)
        .padding(.bottom, style == .scroll ? JoolsSpacing.xxl : JoolsSpacing.lg)
        .accessibilityIdentifier("made-with-jataayu-footer")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Made with love by indrasvat")
    }
}

/// Inline logotype that replaces the capital **J** in "Jools" with the
/// pixel-art glyph. Use this anywhere the product name is shown alongside
/// other type — the pixel letter stays crisp while "ools" flows in the
/// native rounded system font.
struct PixelJoolsLogotype: View {
    var fontSize: CGFloat = 32
    var weight: Font.Weight = .bold
    var design: Font.Design = .rounded
    var color: Color = .primary
    var tracking: CGFloat?

    private var resolvedTracking: CGFloat {
        tracking ?? -fontSize * 0.03
    }

    // Sized so the J's stem (rows 0–10, i.e. the cap-to-baseline portion)
    // roughly matches system rounded bold cap-height (≈0.72 × fontSize),
    // with the descender hook (rows 11–13) poking just below the baseline
    // like a real "J". Tuned empirically in the simulator.
    private var glyphHeight: CGFloat { fontSize * 0.92 }

    private var glyphWidth: CGFloat {
        glyphHeight
            * CGFloat(PixelJoolsPath.gridWidth)
            / CGFloat(PixelJoolsPath.gridHeight)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: fontSize * 0.04) {
            PixelJoolsGlyph(color: color)
                .frame(width: glyphWidth, height: glyphHeight)
                .accessibilityHidden(true)

            Text("ataayu")
                .font(.system(size: fontSize, weight: weight, design: design))
                .tracking(resolvedTracking)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Jataayu")
    }
}

/// Header wordmark — pixel-J logotype with an optional subtitle below.
struct PixelJoolsWordmark: View {
    let titleSize: CGFloat
    let subtitle: String?
    let titleColor: Color

    init(titleSize: CGFloat = 32, subtitle: String? = nil, titleColor: Color = .primary) {
        self.titleSize = titleSize
        self.subtitle = subtitle
        self.titleColor = titleColor
    }

    var body: some View {
        if let subtitle {
            VStack(alignment: .leading, spacing: 2) {
                PixelJoolsLogotype(fontSize: titleSize, color: titleColor)
                Text(subtitle)
                    .font(.joolsCaption)
                    .foregroundStyle(.secondary)
            }
        } else {
            PixelJoolsLogotype(fontSize: titleSize, color: titleColor)
        }
    }
}

struct PixelJoolsBadge<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundFill)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)

            content
        }
        .shadow(color: shadowColor, radius: 16, x: 0, y: 8)
    }

    private var backgroundFill: some ShapeStyle {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.16, green: 0.16, blue: 0.21), Color(red: 0.10, green: 0.10, blue: 0.14)]
                : [Color(red: 0.95, green: 0.93, blue: 0.97), Color(red: 0.90, green: 0.87, blue: 0.94)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.28) : Color.joolsAccent.opacity(0.18)
    }
}

// MARK: - Shared pixel path data
//
// `PixelJoolsPath` is the single source of truth for the brand glyph —
// both the centred `PixelJoolsMark` (used in badges/icons) and the
// baseline-aligned `PixelJoolsGlyph` (used inline with text) read from
// here. The Python icon generator keeps its own copy in
// `scripts/generate_icon.py`; any edit to the pixel map must update both.
enum PixelJoolsPath {
    enum Tone { case shadow, body }

    struct Cell {
        let x: Int
        let y: Int
        let tone: Tone
    }

    static let gridWidth = 11
    static let gridHeight = 14
    static let pixelMap: [String] = [
        ".......BBS.",
        ".......BBSS",
        ".......BBSS",
        ".......BBSS",
        ".......BBSS",
        ".......BBSS",
        ".......BBSS",
        ".......BBSS",
        ".......BBSS",
        ".S.....BBSS",
        "SBB....BBSS",
        "SBBBBBBBBSS",
        ".SBBBBBBSS.",
        "..SSSSSSS..",
    ]

    static let cells: [Cell] = {
        var result: [Cell] = []
        for (y, row) in pixelMap.enumerated() {
            for (x, char) in row.enumerated() {
                switch char {
                case "B": result.append(Cell(x: x, y: y, tone: .body))
                case "S": result.append(Cell(x: x, y: y, tone: .shadow))
                default: break
                }
            }
        }
        return result
    }()

    // Visual centroid (+0.5 to hit cell centres). The J's stem is denser
    // than the hook, so centring on the bounding box pulls the letter
    // off to the right; centroid centring corrects for that.
    static let centroid: (x: CGFloat, y: CGFloat) = {
        let xs = cells.map { CGFloat($0.x) }
        let ys = cells.map { CGFloat($0.y) }
        let mx = xs.reduce(0, +) / CGFloat(xs.count) + 0.5
        let my = ys.reduce(0, +) / CGFloat(ys.count) + 0.5
        return (mx, my)
    }()

    // Effective footprint after centroid centring — the far side needs
    // extra clearance, so cell sizing must use this enlarged footprint.
    static let footprint: (width: CGFloat, height: CGFloat) = {
        let w = 2 * max(centroid.x, CGFloat(gridWidth) - centroid.x)
        let h = 2 * max(centroid.y, CGFloat(gridHeight) - centroid.y)
        return (w, h)
    }()

    // Typographic baseline position, expressed as a fraction of the
    // grid's bounding-box height. Row 11 is the bottom of the hook's
    // horizontal stroke — that's where "ools" should sit. Rows 12-13
    // are the descender curl.
    static let baselineFraction: CGFloat = 11.0 / CGFloat(gridHeight)

    static func bodyColor(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.78, green: 0.66, blue: 1.00)   // light lavender, pops on black
            : Color(red: 0.55, green: 0.36, blue: 0.96)   // brand accent purple
    }

    // The shadow cells form a 1-px drop shadow on the right side of the
    // stem and underneath the hook. In light mode that's a near-black
    // ink, but on a dark background near-black is invisible — so dark
    // mode uses a saturated mid-purple that still reads as "depth"
    // beneath the lavender body without dissolving into the surface.
    static func shadowColor(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.34, green: 0.22, blue: 0.58)   // mid-purple, visible on black
            : Color(red: 0.08, green: 0.06, blue: 0.13)   // near-black ink
    }
}

/// Pixel J centred on its visual centroid inside the supplied frame.
/// Use inside badges or icons where the J should sit visually level in
/// a square container.
struct PixelJoolsMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let cellSize = min(
                geometry.size.width / PixelJoolsPath.footprint.width,
                geometry.size.height / PixelJoolsPath.footprint.height
            )
            let originX = geometry.size.width / 2 - PixelJoolsPath.centroid.x * cellSize
            let originY = geometry.size.height / 2 - PixelJoolsPath.centroid.y * cellSize

            ZStack(alignment: .topLeading) {
                ForEach(Array(PixelJoolsPath.cells.enumerated()), id: \.offset) { _, cell in
                    Rectangle()
                        .fill(color(for: cell.tone))
                        .frame(width: cellSize, height: cellSize)
                        .offset(
                            x: originX + CGFloat(cell.x) * cellSize,
                            y: originY + CGFloat(cell.y) * cellSize
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }

    private func color(for tone: PixelJoolsPath.Tone) -> Color {
        switch tone {
        case .body: return PixelJoolsPath.bodyColor(for: colorScheme)
        case .shadow: return PixelJoolsPath.shadowColor(for: colorScheme)
        }
    }
}

/// Pixel J sized to fill its frame via the grid bounding box (no
/// centroid offset) and published with a `firstTextBaseline` alignment
/// guide so it can sit inline with regular text. Use inside
/// `PixelJoolsLogotype`, not directly.
struct PixelJoolsGlyph: View {
    @Environment(\.colorScheme) private var colorScheme
    var color: Color = .primary
    var useBrandPalette: Bool = true

    var body: some View {
        GeometryReader { geometry in
            let cellSize = min(
                geometry.size.width / CGFloat(PixelJoolsPath.gridWidth),
                geometry.size.height / CGFloat(PixelJoolsPath.gridHeight)
            )
            let gridW = cellSize * CGFloat(PixelJoolsPath.gridWidth)
            let gridH = cellSize * CGFloat(PixelJoolsPath.gridHeight)
            let originX = (geometry.size.width - gridW) / 2
            let originY = (geometry.size.height - gridH) / 2

            ZStack(alignment: .topLeading) {
                ForEach(Array(PixelJoolsPath.cells.enumerated()), id: \.offset) { _, cell in
                    Rectangle()
                        .fill(pixelColor(for: cell.tone))
                        .frame(width: cellSize, height: cellSize)
                        .offset(
                            x: originX + CGFloat(cell.x) * cellSize,
                            y: originY + CGFloat(cell.y) * cellSize
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        // Expose the J's visual baseline so HStack(.firstTextBaseline)
        // lines the hook's horizontal stroke up with the text baseline.
        .alignmentGuide(.firstTextBaseline) { dim in
            dim.height * PixelJoolsPath.baselineFraction
        }
        .alignmentGuide(.lastTextBaseline) { dim in
            dim.height * PixelJoolsPath.baselineFraction
        }
    }

    private func pixelColor(for tone: PixelJoolsPath.Tone) -> Color {
        if useBrandPalette {
            switch tone {
            case .body: return PixelJoolsPath.bodyColor(for: colorScheme)
            case .shadow: return PixelJoolsPath.shadowColor(for: colorScheme)
            }
        }
        // Monochrome fallback that honours the supplied tint for callers
        // that want the J to match surrounding text colour (e.g. an
        // all-white logotype on a coloured splash).
        switch tone {
        case .body: return color
        case .shadow: return color.opacity(0.25)
        }
    }
}
