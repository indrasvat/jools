import SwiftUI
import JoolsKit

// MARK: - File Change Status

enum FileChangeStatus {
    case added
    case modified
    case deleted

    var icon: String {
        switch self {
        case .added: return "plus.circle.fill"
        case .modified: return "pencil.circle.fill"
        case .deleted: return "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .added: return .green
        case .modified: return .orange
        case .deleted: return .red
        }
    }
}

// MARK: - File Pill

/// A tappable pill badge displaying a filename
struct FilePill: View {
    let filename: String
    let status: FileChangeStatus?
    let onTap: () -> Void

    init(filename: String, status: FileChangeStatus? = nil, onTap: @escaping () -> Void) {
        self.filename = filename
        self.status = status
        self.onTap = onTap
    }

    /// Extracts just the filename from a full path
    private var displayName: String {
        filename.components(separatedBy: "/").last ?? filename
    }

    /// File extension for syntax highlighting hints
    private var fileExtension: String {
        filename.components(separatedBy: ".").last ?? ""
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: JoolsSpacing.xxs) {
                // Status indicator (optional)
                if let status = status {
                    Image(systemName: status.icon)
                        .font(.caption2)
                        .foregroundStyle(status.color)
                }

                // File icon based on extension
                Image(systemName: iconForExtension(fileExtension))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Filename
                Text(displayName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, JoolsSpacing.sm)
            .padding(.vertical, JoolsSpacing.xxs)
            .background(Color.joolsSurface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(status?.color.opacity(0.5) ?? Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "html", "htm": return "chevron.left.forwardslash.chevron.right"
        case "css", "scss", "sass": return "paintbrush"
        case "json": return "curlybraces.square"
        case "md", "markdown": return "text.document"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "rb": return "diamond"
        case "yml", "yaml": return "list.bullet.indent"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        default: return "doc"
        }
    }
}

// MARK: - File Update View

/// Shows "Updated" label with file pill badges
struct FileUpdateView: View {
    let files: [String]
    let maxVisible: Int
    let onFileTap: (String) -> Void

    init(files: [String], maxVisible: Int = 3, onFileTap: @escaping (String) -> Void) {
        self.files = files
        self.maxVisible = maxVisible
        self.onFileTap = onFileTap
    }

    var body: some View {
        HStack(spacing: JoolsSpacing.xs) {
            // "Updated" label
            Text("Updated")
                .font(.joolsCaption)
                .foregroundStyle(.secondary)

            // Visible file pills
            ForEach(files.prefix(maxVisible), id: \.self) { file in
                FilePill(filename: file) {
                    onFileTap(file)
                }
            }

            // Overflow indicator
            if files.count > maxVisible {
                Text("and \(files.count - maxVisible) more")
                    .font(.joolsCaption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, JoolsSpacing.md)
    }
}

// MARK: - Files Changed Summary

/// A compact summary of all files changed in a session
struct FilesChangedSummary: View {
    let files: [FileChange]
    let onShowAll: () -> Void

    var addedCount: Int { files.filter { $0.status == .added }.count }
    var modifiedCount: Int { files.filter { $0.status == .modified }.count }
    var deletedCount: Int { files.filter { $0.status == .deleted }.count }

    var body: some View {
        Button(action: onShowAll) {
            HStack(spacing: JoolsSpacing.sm) {
                Image(systemName: "doc.on.doc")
                    .font(.body)
                    .foregroundStyle(Color.joolsAccent)

                Text("\(files.count) files changed")
                    .font(.joolsBody)

                Spacer()

                // Stats
                HStack(spacing: JoolsSpacing.xs) {
                    if addedCount > 0 {
                        StatBadge(count: addedCount, color: .green, icon: "plus")
                    }
                    if modifiedCount > 0 {
                        StatBadge(count: modifiedCount, color: .orange, icon: "pencil")
                    }
                    if deletedCount > 0 {
                        StatBadge(count: deletedCount, color: .red, icon: "minus")
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(JoolsSpacing.md)
            .background(Color.joolsSurface)
            .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, JoolsSpacing.md)
    }
}

// MARK: - File Change Model

struct FileChange: Identifiable {
    let id = UUID()
    let path: String
    let status: FileChangeStatus
    let additions: Int
    let deletions: Int

    var filename: String {
        path.components(separatedBy: "/").last ?? path
    }
}

// MARK: - Stat Badge

private struct StatBadge: View {
    let count: Int
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
            Text("\(count)")
                .font(.caption)
        }
        .foregroundStyle(color)
    }
}

// MARK: - Files List Sheet

/// Sheet showing all changed files with details
struct FilesListSheet: View {
    let files: [FileChange]
    let onFileTap: (FileChange) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Summary section
                Section {
                    HStack {
                        Label("\(files.count) files", systemImage: "doc.on.doc")
                        Spacer()
                        DiffStatsView(
                            additions: files.reduce(0) { $0 + $1.additions },
                            deletions: files.reduce(0) { $0 + $1.deletions }
                        )
                    }
                }

                // Files grouped by status
                ForEach([FileChangeStatus.added, .modified, .deleted], id: \.self) { status in
                    let statusFiles = files.filter { $0.status == status }
                    if !statusFiles.isEmpty {
                        Section(sectionHeader(for: status)) {
                            ForEach(statusFiles) { file in
                                FileRow(file: file) {
                                    onFileTap(file)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Changed Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sectionHeader(for status: FileChangeStatus) -> String {
        switch status {
        case .added: return "Added"
        case .modified: return "Modified"
        case .deleted: return "Deleted"
        }
    }
}

// MARK: - File Row

private struct FileRow: View {
    let file: FileChange
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: file.status.icon)
                    .foregroundStyle(file.status.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.filename)
                        .font(.system(.body, design: .monospaced))

                    Text(file.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: JoolsSpacing.xxs) {
                    Text("+\(file.additions)")
                        .foregroundStyle(.green)
                    Text("-\(file.deletions)")
                        .foregroundStyle(.red)
                }
                .font(.caption.monospaced())
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("File Pills") {
    VStack(spacing: JoolsSpacing.lg) {
        FilePill(filename: "ChatView.swift", status: .modified) {}

        FilePill(filename: "NewFeature.swift", status: .added) {}

        FilePill(filename: "OldCode.swift", status: .deleted) {}

        FileUpdateView(
            files: ["ChatView.swift", "Models.swift", "API.swift", "Tests.swift", "README.md"],
            onFileTap: { _ in }
        )

        FilesChangedSummary(
            files: [
                FileChange(path: "src/ChatView.swift", status: .modified, additions: 45, deletions: 12),
                FileChange(path: "src/NewFile.swift", status: .added, additions: 100, deletions: 0),
                FileChange(path: "src/Legacy.swift", status: .deleted, additions: 0, deletions: 50),
            ],
            onShowAll: {}
        )
    }
    .padding()
    .background(Color.joolsBackground)
}
