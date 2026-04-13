import SwiftUI
import SwiftData

/// Home view showing the current repo context, suggested work, scheduled presets, and recent sessions.
struct DashboardView: View {
    @EnvironmentObject private var dependencies: AppDependency
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SessionEntity.updatedAt, order: .reverse) private var sessions: [SessionEntity]
    @Query private var sources: [SourceEntity]

    @AppStorage("home.selectedSourceID") private var selectedSourceID = ""
    @StateObject private var viewModel = DashboardViewModel()
    @State private var createSessionDraft: CreateSessionDraft?
    @State private var scheduledDraft: ScheduledDraft?
    @State private var showQuickTask = false

    private var sourcesByID: [String: SourceEntity] {
        // Sessions reference their source by either the bare id, the
        // synthesized `sources/<id>` form, or the opaque resource name
        // returned by the API — index all three so attention lookups
        // hit regardless of which form the server returned.
        var index: [String: SourceEntity] = [:]
        for source in sources {
            index[source.id] = source
            index["sources/\(source.id)"] = source
            index[source.name] = source
        }
        return index
    }

    private var selectedSource: SourceEntity? {
        if let source = sources.first(where: { $0.id == selectedSourceID }) {
            return source
        }
        return sources.first
    }

    private var attentionItems: [HomeAttentionItem] {
        HomeContentBuilder.attentionItems(from: sessions, sourcesByID: sourcesByID)
    }

    private var suggestedTasks: [SuggestedTaskTemplate] {
        guard let selectedSource else { return [] }
        return HomeContentBuilder.suggestedTasks(for: selectedSource)
    }

    private var scheduledTemplates: [ScheduledSkillTemplate] {
        guard let selectedSource else { return [] }
        return HomeContentBuilder.scheduledTemplates(for: selectedSource)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: JoolsSpacing.lg) {
                    HomeBrandHeader()
                        .accessibilityIdentifier("home.brand")

                    UsageStatsCard(tasksUsed: viewModel.tasksUsedToday)
                        .accessibilityIdentifier("home.usage")

                    QuickCaptureCard {
                        showQuickTask = true
                    }
                    .accessibilityIdentifier("home.quickCapture")

                    if let errorMessage = viewModel.errorMessage {
                        HomeBanner(
                            title: "Refresh issue",
                            message: errorMessage,
                            style: .error
                        )
                        .accessibilityIdentifier("home.banner.error")
                    }

                    if sources.isEmpty {
                        EmptyDashboardView()
                    } else {
                        NeedsAttentionSection(
                            items: attentionItems,
                            sessionsByID: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
                        )
                        .accessibilityIdentifier("home.section.attention")

                        if let selectedSource {
                            SuggestedSection(
                                source: selectedSource,
                                suggestions: suggestedTasks
                            ) { suggestion in
                                createSessionDraft = CreateSessionDraft(
                                    source: selectedSource,
                                    title: suggestion.title,
                                    prompt: suggestion.prompt,
                                    sessionMode: .review
                                )
                            }
                            .accessibilityIdentifier("home.section.suggested")

                            ScheduledSection(
                                source: selectedSource,
                                templates: scheduledTemplates
                            ) { template in
                                scheduledDraft = ScheduledDraft(
                                    source: selectedSource,
                                    template: template
                                )
                            }
                            .accessibilityIdentifier("home.section.scheduled")
                        }

                        SourcesSection(
                            sources: sources,
                            selectedSourceID: selectedSource?.id,
                            onSelect: { selectedSourceID = $0.id },
                            onCreate: { source in
                                createSessionDraft = CreateSessionDraft(
                                    source: source,
                                    title: "",
                                    prompt: "",
                                    sessionMode: .interactivePlan
                                )
                            }
                        )
                        .accessibilityIdentifier("home.section.sources")

                        if !sessions.isEmpty {
                            RecentSessionsSection(sessions: Array(sessions.prefix(5)))
                                .accessibilityIdentifier("home.section.recentSessions")
                        }

                        MadeWithJoolsFooter()
                    }
                }
                .padding()
            }
            .background(Color.joolsBackground)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let selectedSource {
                        Button {
                            createSessionDraft = CreateSessionDraft(
                                source: selectedSource,
                                title: "",
                                prompt: "",
                                sessionMode: .interactivePlan
                            )
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityIdentifier("home.quickCreate")
                    }

                    Button(action: { viewModel.refresh(using: dependencies, modelContext: modelContext) }) {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, options: .repeating, isActive: viewModel.isLoading)
                    }
                    .accessibilityIdentifier("home.refresh")
                }
            }
            .refreshable {
                await viewModel.refreshAsync(using: dependencies, modelContext: modelContext)
            }
            .sheet(item: $createSessionDraft) { draft in
                CreateSessionView(
                    source: draft.source,
                    initialPrompt: draft.prompt,
                    initialTitle: draft.title,
                    initialSessionMode: draft.sessionMode
                )
            }
            .sheet(isPresented: $showQuickTask) {
                CreateSessionView(source: nil, initialSessionMode: .start)
            }
            .sheet(item: $scheduledDraft) { draft in
                ScheduledTaskComposerView(source: draft.source, template: draft.template)
            }
        }
        .task {
            guard !dependencies.isUITestMode else { return }
            await viewModel.refreshAsync(using: dependencies, modelContext: modelContext)
            syncSelectedSource()
        }
        .onAppear {
            syncSelectedSource()
        }
        .onChange(of: sources.count) { _, _ in
            syncSelectedSource()
        }
    }

    private func syncSelectedSource() {
        guard !sources.isEmpty else {
            selectedSourceID = ""
            return
        }

        if sources.contains(where: { $0.id == selectedSourceID }) {
            return
        }

        selectedSourceID = sources[0].id
    }
}

private struct CreateSessionDraft: Identifiable {
    let source: SourceEntity
    let title: String
    let prompt: String
    let sessionMode: SessionMode

    var id: String {
        "\(source.id)-\(title)-\(prompt.prefix(12))"
    }
}

private struct ScheduledDraft: Identifiable {
    let source: SourceEntity
    let template: ScheduledSkillTemplate

    var id: String {
        "\(source.id)-\(template.id)"
    }
}

private struct HomeBrandHeader: View {
    var body: some View {
        HStack(alignment: .center) {
            PixelJoolsWordmark(
                titleSize: 26,
                subtitle: "An unofficial Jules client"
            )

            Spacer()
        }
        .padding(.top, JoolsSpacing.xs)
    }
}

struct UsageStatsCard: View {
    let tasksUsed: Int

    private var taskWord: String {
        tasksUsed == 1 ? "task" : "tasks"
    }

    private var subtitle: String {
        if tasksUsed == 0 {
            return "Ready for another focused session."
        }
        return "Jules has worked on \(tasksUsed) \(taskWord) for you so far today."
    }

    var body: some View {
        // The Jules REST API doesn't expose plan-tier limits, so we don't
        // claim a denominator we can't verify. Just show the honest count.
        HStack(alignment: .center, spacing: JoolsSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.joolsAccent.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: "sparkles")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.joolsAccent)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: JoolsSpacing.xs) {
                    Text("Today")
                        .font(.joolsHeadline)
                    Text("\(tasksUsed) \(taskWord)")
                        .font(.joolsCaption.weight(.medium))
                        .foregroundStyle(Color.joolsAccent)
                }
                Text(subtitle)
                    .font(.joolsCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .background(Color.joolsSurface)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today, \(tasksUsed) \(taskWord)")
    }
}

private struct HomeBanner: View {
    let title: String
    let message: String
    let style: HomeSectionStyle

    var body: some View {
        HStack(alignment: .top, spacing: JoolsSpacing.sm) {
            Circle()
                .fill(style.tint)
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
                Text(title)
                    .font(.joolsHeadline)
                Text(message)
                    .font(.joolsCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(style.background)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
    }
}

private struct NeedsAttentionSection: View {
    let items: [HomeAttentionItem]
    let sessionsByID: [String: SessionEntity]

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            sectionHeader(title: "Needs Attention", meta: items.isEmpty ? "All clear" : "\(items.count)")

            if items.isEmpty {
                HomeBanner(
                    title: "All clear",
                    message: "Nothing urgent needs your attention right now.",
                    style: .success
                )
            } else {
                ForEach(items) { item in
                    if let session = sessionsByID[item.sessionID] {
                        NavigationLink {
                            ChatView(session: session)
                        } label: {
                            AttentionCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct AttentionCard: View {
    let item: HomeAttentionItem

    var body: some View {
        HStack(alignment: .top, spacing: JoolsSpacing.sm) {
            Image(systemName: iconName)
                .font(.callout)
                .foregroundStyle(item.style.tint)
                .frame(width: 36, height: 36)
                .background(item.style.background)
                .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.sm))

            VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
                Text(item.title)
                    .font(.joolsHeadline)
                    .foregroundStyle(.primary)

                Text(item.subtitle)
                    .font(.joolsCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.actionTitle)
                    .font(.joolsCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(item.style.tint)
                    .padding(.top, JoolsSpacing.xxs)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding()
        .background(Color.joolsSurface)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
    }

    private var iconName: String {
        switch item.style {
        case .info:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .success:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.bubble"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}

private struct SuggestedSection: View {
    let source: SourceEntity
    let suggestions: [SuggestedTaskTemplate]
    let onStart: (SuggestedTaskTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            sectionHeader(title: "Suggested", meta: source.repo)

            ForEach(suggestions) { suggestion in
                SuggestedTaskCard(suggestion: suggestion) {
                    onStart(suggestion)
                }
            }
        }
    }
}

private struct SuggestedTaskCard: View {
    let suggestion: SuggestedTaskTemplate
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            HStack(alignment: .top, spacing: JoolsSpacing.sm) {
                Image(systemName: suggestion.category.icon)
                    .font(.callout)
                    .foregroundStyle(suggestion.category.accent)
                    .frame(width: 36, height: 36)
                    .background(suggestion.category.accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.sm))

                VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
                    Text(suggestion.title)
                        .font(.joolsHeadline)
                    Text(suggestion.rationale)
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ConfidenceBars(level: suggestion.confidence)
            }

            HStack {
                CategoryBadge(category: suggestion.category)
                Spacer()
                Button("Start", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .tint(.joolsAccent)
                    .accessibilityIdentifier("home.suggestion.start.\(suggestion.id)")
            }
        }
        .padding()
        .background(Color.joolsSurface)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
    }
}

private struct ConfidenceBars: View {
    let level: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < level ? Color.joolsSuccess : Color.joolsSuccess.opacity(0.18))
                    .frame(width: 5, height: CGFloat(10 + (index * 4)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Confidence \(confidenceLabel)")
    }

    private var confidenceLabel: String {
        switch level {
        case 4:
            return "very high"
        case 3:
            return "high"
        case 2:
            return "moderate"
        default:
            return "low"
        }
    }
}

private struct CategoryBadge: View {
    let category: SuggestedTaskCategory

    var body: some View {
        HStack(spacing: JoolsSpacing.xxs) {
            Image(systemName: category.icon)
            Text(category.title)
        }
        .font(.joolsCaption)
        .foregroundStyle(category.accent)
        .padding(.horizontal, JoolsSpacing.sm)
        .padding(.vertical, JoolsSpacing.xs)
        .background(category.accent.opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct ScheduledSection: View {
    let source: SourceEntity
    let templates: [ScheduledSkillTemplate]
    let onSelect: (ScheduledSkillTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            sectionHeader(title: "Scheduled", meta: source.repo)

            HomeBanner(
                title: "Schedule skill-based agents",
                message: "Use the official Jules presets and finish creation in the web Scheduled tab until the public API catches up.",
                style: .info
            )

            ForEach(templates) { template in
                ScheduledTemplateCard(template: template) {
                    onSelect(template)
                }
            }
        }
    }
}

private struct ScheduledTemplateCard: View {
    let template: ScheduledSkillTemplate
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: JoolsSpacing.sm) {
            Image(systemName: template.icon)
                .font(.title3)
                .foregroundStyle(template.accent)
                .frame(width: 42, height: 42)
                .background(template.accent.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))

            VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
                Text(template.name)
                    .font(.joolsHeadline)
                Text(template.subtitle)
                    .font(.joolsCaption)
                    .foregroundStyle(.secondary)
                Text(template.details)
                    .font(.joolsCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button("Schedule", action: onOpen)
                .buttonStyle(.bordered)
                .tint(.joolsAccent)
                .accessibilityIdentifier("home.scheduled.open.\(template.id)")
        }
        .padding()
        .background(Color.joolsSurface)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
    }
}

struct SourcesSection: View {
    let sources: [SourceEntity]
    let selectedSourceID: String?
    let onSelect: (SourceEntity) -> Void
    let onCreate: (SourceEntity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            sectionHeader(title: "Sources", meta: "\(sources.count)")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: JoolsSpacing.sm) {
                    ForEach(sources, id: \.id) { source in
                        SourceChip(
                            source: source,
                            isSelected: source.id == selectedSourceID,
                            onSelect: { onSelect(source) },
                            onCreate: { onCreate(source) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct SourceChip: View {
    let source: SourceEntity
    let isSelected: Bool
    let onSelect: () -> Void
    let onCreate: () -> Void

    var body: some View {
        HStack(spacing: JoolsSpacing.xs) {
            Button(action: onSelect) {
                HStack(spacing: JoolsSpacing.xs) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(isSelected ? Color.white : Color.joolsAccent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(source.repo)
                            .font(.joolsBody)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(source.owner)
                            .font(.joolsCaption)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.82) : .secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, JoolsSpacing.md)
                .padding(.vertical, JoolsSpacing.sm)
                .background(isSelected ? Color.joolsAccent : Color.joolsSurface)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.source.select.\(source.id)")

            Button(action: onCreate) {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(Color.joolsAccent.opacity(0.72))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.source.create.\(source.id)")
        }
    }
}

struct RecentSessionsSection: View {
    let sessions: [SessionEntity]

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            HStack {
                Text("Recent Sessions")
                    .font(.joolsHeadline)
                Spacer()
                NavigationLink("See All") {
                    SessionsListView()
                }
                .font(.joolsCaption)
            }

            ForEach(sessions, id: \.id) { session in
                SessionRow(session: session)
            }
        }
    }
}

struct SessionRow: View {
    let session: SessionEntity

    var body: some View {
        let resolved = session.resolvedState

        NavigationLink {
            ChatView(session: session)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
                    Text(session.title)
                        .font(.joolsBody)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(session.prompt)
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                SessionStateBadge(resolved: resolved)
            }
            .padding()
            .background(Color.joolsSurface)
            .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        }
        .buttonStyle(.plain)
    }
}

struct EmptyDashboardView: View {
    var body: some View {
        VStack(spacing: JoolsSpacing.md) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Sources Yet")
                .font(.joolsTitle3)

            Text("Refresh after connecting a repository in Jules web, then return here for suggestions and scheduled presets.")
                .font(.joolsBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, JoolsSpacing.xxl)
    }
}

private func sectionHeader(title: String, meta: String) -> some View {
    HStack {
        Text(title)
            .font(.joolsHeadline)
        Spacer()
        Text(meta)
            .font(.joolsCaption)
            .foregroundStyle(.secondary)
    }
}

/// Repoless quick-capture entry on Home. The whole card is one tap
/// target — drop a thought, no repo, no branch picker.
struct QuickCaptureCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: JoolsSpacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.joolsAccent.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.joolsAccent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick task")
                        .font(.joolsHeadline)
                        .foregroundStyle(.primary)
                    Text("Hand Jules a self-contained task without picking a repo.")
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color.joolsSurface)
            .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppDependency())
}
