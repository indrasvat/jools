import Foundation
import SwiftUI
import JoolsKit
import Markdown

// MARK: - FlatMarkdownRenderer
//
// Converts a markdown source string into a flat `[MarkdownSegment]`
// sequence. Most input produces a small number of segments: a
// single `.text` segment packing all paragraphs/headings/lists/
// blockquotes via attributed-string paragraph styles, plus
// separate `.codeBlock` / `.table` / `.thematicBreak` segments
// for structural blocks that genuinely need their own view.
//
// Why this exists: the previous `MarkdownText` view produced a
// nested SwiftUI view tree (~50 views per agent message) because
// it created one SwiftUI subview per block AND per inline node.
// Under sustained scroll + polling, that view tree is what
// drove the LazyVStack measurement loop to saturate the main
// thread. The Jules web UI, by contrast, outputs ~3 flat HTML
// elements per block — and that's what keeps scroll performance
// bounded. The flat-renderer approach is the SwiftUI equivalent.
//
// The renderer is a pure function: `render(_ markdown: String) ->
// [MarkdownSegment]`. It uses the process-wide
// `MarkdownDocumentCache` so repeated calls on the same source
// return in constant time. It runs on whatever thread calls it;
// snapshot construction currently runs on the main actor but the
// output is Sendable so this can move later.
enum FlatMarkdownRenderer {

    /// Render a markdown source string into a flat segment sequence.
    static func render(_ markdown: String) -> [MarkdownSegment] {
        guard !markdown.isEmpty else { return [] }
        let document = MarkdownDocumentCache.shared.document(for: markdown)
        var builder = SegmentBuilder()
        for block in document.blockChildren {
            builder.append(block: block)
        }
        return builder.finish()
    }

    // MARK: - Segment builder
    //
    // Accumulates adjacent "text-ish" blocks (paragraphs, headings,
    // lists, blockquotes) into a single AttributedString, flushing
    // it as a `.text` segment when a structural block (code, table,
    // thematic break) interrupts the run. This is why a typical
    // agent message with 5 paragraphs + 1 table + 1 code block
    // produces 4 segments instead of 7: the text runs on either
    // side of the structural blocks are packed into one segment
    // each.
    private struct SegmentBuilder {
        private var currentText = AttributedString()
        private var segmentIndex: Int = 0
        private var output: [MarkdownSegment] = []

        mutating func append(block: any BlockMarkup) {
            switch block {
            case let paragraph as Paragraph:
                appendParagraph(paragraph)

            case let heading as Heading:
                appendHeading(heading)

            case let unorderedList as UnorderedList:
                appendList(unorderedList, ordered: false)

            case let orderedList as OrderedList:
                appendList(orderedList, ordered: true)

            case let blockQuote as BlockQuote:
                appendBlockQuote(blockQuote)

            case let codeBlock as CodeBlock:
                flushTextSegment()
                output.append(.codeBlock(
                    id: makeSegmentID(kind: "code"),
                    language: codeBlock.language,
                    code: codeBlock.code.hasSuffix("\n") ? String(codeBlock.code.dropLast()) : codeBlock.code
                ))

            case let table as Markdown.Table:
                flushTextSegment()
                output.append(tableSegment(from: table))

            case is ThematicBreak:
                flushTextSegment()
                output.append(.thematicBreak(id: makeSegmentID(kind: "hr")))

            default:
                // Unknown block type — degrade to its raw text so
                // we never drop authored content silently.
                appendRawParagraph(String(block.format()))
            }
        }

        mutating func finish() -> [MarkdownSegment] {
            flushTextSegment()
            return output
        }

        // MARK: Text-run accumulation

        private mutating func appendParagraph(_ paragraph: Paragraph) {
            var run = InlineAttributedStringBuilder.build(from: paragraph)
            run.mergeAttributes(paragraphStyleAttributes(indent: 0))
            currentText.append(run)
            appendNewline()
        }

        private mutating func appendHeading(_ heading: Heading) {
            var run = InlineAttributedStringBuilder.build(from: heading)
            let headingFont: Font
            switch heading.level {
            case 1: headingFont = .system(.title2).weight(.bold)
            case 2: headingFont = .system(.title3).weight(.bold)
            case 3: headingFont = .system(.headline).weight(.bold)
            default: headingFont = .system(.subheadline).weight(.bold)
            }
            run.font = headingFont
            run.mergeAttributes(paragraphStyleAttributes(indent: 0))
            currentText.append(run)
            appendNewline()
        }

        private mutating func appendList(_ list: any ListItemContainer, ordered: Bool) {
            let items = Array(list.listItems)
            for (index, item) in items.enumerated() {
                let prefix: String = ordered ? "\(index + 1). " : "• "
                var prefixRun = AttributedString(prefix)
                prefixRun.font = .joolsBody
                prefixRun.foregroundColor = .secondary
                prefixRun.mergeAttributes(paragraphStyleAttributes(indent: 16))
                currentText.append(prefixRun)

                // Materialize the item's block children to an Array
                // once so we can index into it. `BlockChildren` is a
                // Sequence, not a RandomAccessCollection — it lacks
                // a `.count` property and iteration-index lookup.
                let itemBlocks = Array(item.blockChildren)
                for (blockIndex, block) in itemBlocks.enumerated() {
                    if let paragraph = block as? Paragraph {
                        var run = InlineAttributedStringBuilder.build(from: paragraph)
                        run.mergeAttributes(paragraphStyleAttributes(indent: 16))
                        currentText.append(run)
                    } else if let nestedUL = block as? UnorderedList {
                        // Nested unordered list — render each sub-item
                        // with deeper indent and inline formatting.
                        appendNewline()
                        appendNestedList(nestedUL, indent: 32)
                    } else if let nestedOL = block as? OrderedList {
                        appendNewline()
                        appendNestedList(nestedOL, indent: 32)
                    } else {
                        // Other nested blocks — render with inline
                        // formatting so bold/code/links are preserved.
                        var run = InlineAttributedStringBuilder.build(from: block as Markup)
                        run.mergeAttributes(paragraphStyleAttributes(indent: 32))
                        currentText.append(run)
                    }
                    if blockIndex < itemBlocks.count - 1 {
                        appendNewline()
                    }
                }
                appendNewline()
            }
        }

        /// Render a nested list (inside a parent list item) with
        /// proper indentation and inline formatting (bold, code, etc).
        private mutating func appendNestedList(_ list: any ListItemContainer, indent: CGFloat) {
            let items = Array(list.listItems)
            let ordered = list is OrderedList
            for (index, item) in items.enumerated() {
                let prefix: String = ordered ? "\(index + 1). " : "– "
                var prefixRun = AttributedString(prefix)
                prefixRun.font = .joolsBody
                prefixRun.foregroundColor = .secondary
                prefixRun.mergeAttributes(paragraphStyleAttributes(indent: indent))
                currentText.append(prefixRun)

                for block in item.blockChildren {
                    if let paragraph = block as? Paragraph {
                        var run = InlineAttributedStringBuilder.build(from: paragraph)
                        run.mergeAttributes(paragraphStyleAttributes(indent: indent))
                        currentText.append(run)
                    } else {
                        var run = InlineAttributedStringBuilder.build(from: block as Markup)
                        run.mergeAttributes(paragraphStyleAttributes(indent: indent + 16))
                        currentText.append(run)
                    }
                }
                appendNewline()
            }
        }

        private mutating func appendBlockQuote(_ blockQuote: BlockQuote) {
            // Render blockquote contents with secondary color and
            // indent. Proper vertical rule rendering isn't something
            // NSAttributedString easily supports on iOS, so we use
            // an em-dash-style left margin via paragraph indent +
            // secondary color.
            for block in blockQuote.blockChildren {
                if let paragraph = block as? Paragraph {
                    var run = InlineAttributedStringBuilder.build(from: paragraph)
                    run.foregroundColor = .secondary
                    run.mergeAttributes(paragraphStyleAttributes(indent: 16))
                    currentText.append(run)
                    appendNewline()
                }
            }
        }

        private mutating func appendRawParagraph(_ text: String) {
            var run = AttributedString(text)
            run.font = .joolsBody
            currentText.append(run)
            appendNewline()
        }

        private mutating func appendNewline() {
            currentText.append(AttributedString("\n"))
        }

        private mutating func flushTextSegment() {
            // Trim trailing newlines so adjacent segments don't
            // accumulate extra blank lines.
            let trimmed = currentText.trimmingTrailingNewlines()
            guard !trimmed.characters.isEmpty else {
                currentText = AttributedString()
                return
            }
            output.append(.text(
                id: makeSegmentID(kind: "text"),
                attributed: trimmed
            ))
            currentText = AttributedString()
        }

        // MARK: Table

        private mutating func tableSegment(from table: Markdown.Table) -> MarkdownSegment {
            let head = Array(table.head.cells).map {
                InlineAttributedStringBuilder.build(from: $0 as Markup)
            }
            let rows = Array(table.body.rows).map { row in
                Array(row.cells).map {
                    InlineAttributedStringBuilder.build(from: $0 as Markup)
                }
            }
            return .table(
                id: makeSegmentID(kind: "table"),
                head: head,
                rows: rows
            )
        }

        // MARK: Utilities

        private mutating func makeSegmentID(kind: String) -> String {
            defer { segmentIndex += 1 }
            return "\(kind)-\(segmentIndex)"
        }
    }
}

// MARK: - Paragraph style helper
//
// `AttributedString` on iOS carries paragraph-style info via the
// Foundation attribute namespace. We need just a few properties:
// a head indent (for list items / blockquotes) and a line-break
// mode. The base font comes from the inline-run attributes set
// by `InlineAttributedStringBuilder`.

private func paragraphStyleAttributes(indent: CGFloat) -> AttributeContainer {
    var container = AttributeContainer()
    var paragraph = NSMutableParagraphStyle()
    paragraph.headIndent = indent
    paragraph.firstLineHeadIndent = max(0, indent - 16)
    paragraph.paragraphSpacing = 4
    paragraph.lineBreakMode = .byWordWrapping
    container.uiKit.paragraphStyle = paragraph
    return container
}

// MARK: - Trim helper

private extension AttributedString {
    /// Drops trailing newline characters. Used when flushing a
    /// text segment so adjacent segments don't accumulate extra
    /// blank lines.
    func trimmingTrailingNewlines() -> AttributedString {
        var copy = self
        while let last = copy.characters.last, last == "\n" {
            copy.removeSubrange(copy.index(beforeCharacter: copy.endIndex)..<copy.endIndex)
        }
        return copy
    }

    /// Safe backward index step — `AttributedString` doesn't
    /// expose `index(before:)` directly at the `CharacterView`
    /// level so we route through offset arithmetic.
    func index(beforeCharacter _: AttributedString.Index) -> AttributedString.Index {
        return self.index(self.endIndex, offsetByCharacters: -1)
    }
}
