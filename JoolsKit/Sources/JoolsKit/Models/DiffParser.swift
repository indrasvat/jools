import Foundation

// MARK: - Public types

/// A single line within a diff hunk, classified for rendering.
public struct DiffLine: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case context
        case addition
        case deletion
        case header
    }

    public let id: Int
    public let kind: Kind
    public let content: String
    /// 1-based old-file line number (nil for additions and headers).
    public let oldLineNumber: Int?
    /// 1-based new-file line number (nil for deletions and headers).
    public let newLineNumber: Int?

    public init(id: Int, kind: Kind, content: String, oldLineNumber: Int?, newLineNumber: Int?) {
        self.id = id
        self.kind = kind
        self.content = content
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }
}

/// A contiguous group of changed lines (one `@@` block in a unified diff).
public struct DiffHunk: Sendable, Equatable, Identifiable {
    public let id: Int
    public let header: String
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [DiffLine]

    public init(
        id: Int,
        header: String,
        oldStart: Int,
        oldCount: Int,
        newStart: Int,
        newCount: Int,
        lines: [DiffLine]
    ) {
        self.id = id
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

/// One file's worth of unified-diff content.
public struct DiffFile: Sendable, Equatable, Identifiable {
    public enum ChangeKind: Sendable, Equatable {
        case modified
        case added
        case removed
        case renamed(from: String)
    }

    public var id: String { path }
    public let path: String
    public let oldPath: String?
    public let kind: ChangeKind
    public let hunks: [DiffHunk]
    public let additions: Int
    public let deletions: Int

    public init(
        path: String,
        oldPath: String?,
        kind: ChangeKind,
        hunks: [DiffHunk],
        additions: Int,
        deletions: Int
    ) {
        self.path = path
        self.oldPath = oldPath
        self.kind = kind
        self.hunks = hunks
        self.additions = additions
        self.deletions = deletions
    }

    public var isBinary: Bool { hunks.isEmpty && additions == 0 && deletions == 0 }
}

// MARK: - Parser

/// Parses the subset of unified-diff syntax Jules emits in
/// `changeSet.gitPatch.unidiffPatch`. Robust enough for read-only
/// rendering — not a general-purpose diff library.
public enum UnifiedDiffParser {
    public static func parse(_ patch: String) -> [DiffFile] {
        var files: [DiffFile] = []
        let lines = patch.components(separatedBy: "\n")

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // Each file block starts with `diff --git a/<old> b/<new>`.
            if line.hasPrefix("diff --git ") {
                let (file, advance) = parseFileBlock(lines: lines, startIndex: i)
                if let file {
                    files.append(file)
                }
                i = advance
                continue
            }

            i += 1
        }

        return files
    }

    private static func parseFileBlock(lines: [String], startIndex: Int) -> (DiffFile?, Int) {
        let header = lines[startIndex]
        var oldPath: String?
        var newPath: String?
        var kind: DiffFile.ChangeKind = .modified
        var hunks: [DiffHunk] = []
        var additions = 0
        var deletions = 0
        var lineId = 0
        var hunkId = 0

        // Parse `diff --git a/<old> b/<new>` to seed the path. Jules
        // sometimes uses `/dev/null` for added/deleted files inside
        // the `---` / `+++` markers, so we wait for those before
        // settling on the canonical path.
        let parts = header.dropFirst("diff --git ".count).split(separator: " ", maxSplits: 1)
        if parts.count == 2 {
            oldPath = String(parts[0]).strippingPrefix("a/")
            newPath = String(parts[1]).strippingPrefix("b/")
        }

        var i = startIndex + 1
        while i < lines.count {
            let line = lines[i]

            // End of this file's block — next `diff --git` belongs
            // to a sibling file.
            if line.hasPrefix("diff --git ") {
                break
            }

            if line.hasPrefix("--- ") {
                let raw = String(line.dropFirst("--- ".count))
                if raw == "/dev/null" {
                    kind = .added
                } else {
                    oldPath = raw.strippingPrefix("a/")
                }
                i += 1
                continue
            }

            if line.hasPrefix("+++ ") {
                let raw = String(line.dropFirst("+++ ".count))
                if raw == "/dev/null" {
                    kind = .removed
                } else {
                    newPath = raw.strippingPrefix("b/")
                }
                i += 1
                continue
            }

            if line.hasPrefix("rename from ") {
                let from = String(line.dropFirst("rename from ".count))
                kind = .renamed(from: from)
                i += 1
                continue
            }

            if line.hasPrefix("Binary files ") {
                // Binary file — keep the file entry but no hunks.
                i += 1
                continue
            }

            if line.hasPrefix("@@") {
                let (hunk, consumed) = parseHunk(
                    lines: lines,
                    startIndex: i,
                    seedLineId: lineId,
                    hunkId: hunkId
                )
                if let hunk {
                    hunks.append(hunk)
                    additions += hunk.lines.filter { $0.kind == .addition }.count
                    deletions += hunk.lines.filter { $0.kind == .deletion }.count
                    lineId += hunk.lines.count + 1 // +1 for header
                    hunkId += 1
                }
                i = consumed
                continue
            }

            i += 1
        }

        let resolvedPath = newPath ?? oldPath ?? "<unknown>"
        return (
            DiffFile(
                path: resolvedPath,
                oldPath: oldPath,
                kind: kind,
                hunks: hunks,
                additions: additions,
                deletions: deletions
            ),
            i
        )
    }

    private static func parseHunk(
        lines: [String],
        startIndex: Int,
        seedLineId: Int,
        hunkId: Int
    ) -> (DiffHunk?, Int) {
        let header = lines[startIndex]
        guard let parsed = parseHunkHeader(header) else {
            return (nil, startIndex + 1)
        }

        var hunkLines: [DiffLine] = []
        var oldLine = parsed.oldStart
        var newLine = parsed.newStart
        var nextId = seedLineId

        var i = startIndex + 1
        while i < lines.count {
            let raw = lines[i]
            // End of this hunk: any new file marker, hunk marker, or
            // EOF terminator.
            if raw.hasPrefix("@@") || raw.hasPrefix("diff --git ") || raw.hasPrefix("--- ") || raw.hasPrefix("+++ ") {
                break
            }

            // Skip "\ No newline at end of file" markers — they're
            // metadata, not content.
            if raw.hasPrefix("\\ ") {
                i += 1
                continue
            }

            let kind: DiffLine.Kind
            let content: String
            let oldNumber: Int?
            let newNumber: Int?

            if raw.hasPrefix("+") {
                kind = .addition
                content = String(raw.dropFirst())
                oldNumber = nil
                newNumber = newLine
                newLine += 1
            } else if raw.hasPrefix("-") {
                kind = .deletion
                content = String(raw.dropFirst())
                oldNumber = oldLine
                newNumber = nil
                oldLine += 1
            } else {
                kind = .context
                // Context lines may or may not have a leading space —
                // tolerate both.
                content = raw.hasPrefix(" ") ? String(raw.dropFirst()) : raw
                oldNumber = oldLine
                newNumber = newLine
                oldLine += 1
                newLine += 1
            }

            hunkLines.append(
                DiffLine(
                    id: nextId,
                    kind: kind,
                    content: content,
                    oldLineNumber: oldNumber,
                    newLineNumber: newNumber
                )
            )
            nextId += 1
            i += 1
        }

        let hunk = DiffHunk(
            id: hunkId,
            header: header,
            oldStart: parsed.oldStart,
            oldCount: parsed.oldCount,
            newStart: parsed.newStart,
            newCount: parsed.newCount,
            lines: hunkLines
        )
        return (hunk, i)
    }

    /// Parsed `@@ -<oldStart>,<oldCount> +<newStart>,<newCount> @@` header.
    private struct ParsedHunkHeader {
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
    }

    /// Parses a hunk header like `@@ -10,7 +10,8 @@ optional context`.
    private static func parseHunkHeader(_ header: String) -> ParsedHunkHeader? {
        // Strip the leading `@@ ` and trailing ` @@ ...` so we're left
        // with `-10,7 +10,8`.
        guard let firstAt = header.range(of: "@@") else { return nil }
        let afterFirst = header[firstAt.upperBound...]
        guard let secondAt = afterFirst.range(of: "@@") else { return nil }
        let body = afterFirst[..<secondAt.lowerBound].trimmingCharacters(in: .whitespaces)
        let pieces = body.split(separator: " ")
        guard pieces.count >= 2 else { return nil }
        let oldRange = pieces[0]   // -10,7
        let newRange = pieces[1]   // +10,8
        guard
            let old = parseRange(String(oldRange.dropFirst())),
            let new = parseRange(String(newRange.dropFirst()))
        else {
            return nil
        }
        return ParsedHunkHeader(
            oldStart: old.start,
            oldCount: old.count,
            newStart: new.start,
            newCount: new.count
        )
    }

    private static func parseRange(_ raw: String) -> (start: Int, count: Int)? {
        let parts = raw.split(separator: ",")
        guard let start = Int(parts.first ?? "") else { return nil }
        let count: Int
        if parts.count > 1, let parsed = Int(parts[1]) {
            count = parsed
        } else {
            count = 1
        }
        return (start, count)
    }
}

// MARK: - Convenience hooks on the existing patch DTO

public extension GitPatchDTO {
    /// Structured per-file view of the patch — convenience for any UI
    /// that wants to show hunks instead of the raw unified-diff blob.
    var parsedFiles: [DiffFile] {
        guard let content = patchContent else { return [] }
        return UnifiedDiffParser.parse(content)
    }
}

private extension String {
    func strippingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else { return self }
        return String(dropFirst(prefix.count))
    }
}
