import SwiftUI
import JoolsKit

// MARK: - Plan Card with Collapsible Steps

/// A card displaying a proposed plan with expandable step details
struct PlanCardView: View {
    let activity: ActivityEntity
    let onApprove: () -> Void
    let onRevise: () -> Void

    @State private var isExpanded = true
    @State private var expandedSteps: Set<Int> = []

    private var planSteps: [PlanStepDTO] {
        guard let content = try? JSONDecoder().decode(ActivityContentDTO.self, from: activity.contentJSON),
              let plan = content.plan,
              let steps = plan.steps else {
            return []
        }
        return steps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with Hide/Show toggle
            header

            if isExpanded {
                Divider()
                    .padding(.horizontal, JoolsSpacing.md)

                // Steps list
                stepsContent

                Divider()
                    .padding(.horizontal, JoolsSpacing.md)

                // Action buttons
                actionButtons
            }
        }
        .background(Color.joolsSurface)
        .overlay(
            RoundedRectangle(cornerRadius: JoolsRadius.md)
                .stroke(Color.joolsPlanBorder, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        .padding(.horizontal, JoolsSpacing.md)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundStyle(Color.joolsPlanBorder)

            Text("Proposed Plan")
                .font(.joolsHeadline)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Text(isExpanded ? "Hide" : "Show")
                    .font(.joolsCaption)
                    .foregroundStyle(Color.joolsAccent)
            }
        }
        .padding(JoolsSpacing.md)
    }

    private var stepsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if planSteps.isEmpty {
                Text("Plan details would appear here...")
                    .font(.joolsBody)
                    .foregroundStyle(.secondary)
                    .padding(JoolsSpacing.md)
            } else {
                ForEach(Array(planSteps.enumerated()), id: \.offset) { index, step in
                    PlanStepRow(
                        number: index + 1,
                        step: step,
                        isExpanded: expandedSteps.contains(index),
                        onToggle: { toggleStep(index) }
                    )

                    if index < planSteps.count - 1 {
                        Divider()
                            .padding(.leading, JoolsSpacing.xl + JoolsSpacing.md)
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: JoolsSpacing.md) {
            Button(action: onRevise) {
                Label("Revise", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: onApprove) {
                Label("Approve", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.joolsAccent)
        }
        .padding(JoolsSpacing.md)
    }

    // MARK: - Actions

    private func toggleStep(_ index: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedSteps.contains(index) {
                expandedSteps.remove(index)
            } else {
                expandedSteps.insert(index)
            }
        }
    }
}

// MARK: - Plan Step Row

struct PlanStepRow: View {
    let number: Int
    let step: PlanStepDTO
    let isExpanded: Bool
    let onToggle: () -> Void

    private var stepStatus: StepStatus {
        guard let status = step.status else { return .pending }
        switch status.lowercased() {
        case "completed", "done": return .completed
        case "in_progress", "running": return .inProgress
        default: return .pending
        }
    }

    /// Whether this row has content beyond its title to disclose.
    /// We hide the chevron entirely when there's nothing to expand so
    /// the affordance never lies — earlier the chevron rotated on tap
    /// even when the description was nil, which felt broken.
    private var hasExpandableDescription: Bool {
        guard let description = step.description, !description.isEmpty else {
            return false
        }
        // If the only "description" is the same string we use as the
        // title, expansion would be a no-op duplicate.
        if let title = step.title, title == description {
            return false
        }
        return true
    }

    private var displayTitle: String {
        step.title ?? step.description ?? "Step \(number)"
    }

    var body: some View {
        Group {
            if hasExpandableDescription {
                Button(action: onToggle) {
                    rowContent
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plan.step.\(number)")
                .accessibilityHint(isExpanded ? "Hides step details" : "Shows step details")
            } else {
                rowContent
                    .accessibilityIdentifier("plan.step.\(number)")
            }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: JoolsSpacing.sm) {
                StepNumberBadge(number: number, status: stepStatus)

                Text(displayTitle)
                    .font(.joolsBody)
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 2)
                    .multilineTextAlignment(.leading)

                Spacer()

                if hasExpandableDescription {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .padding(.horizontal, JoolsSpacing.md)
            .padding(.vertical, JoolsSpacing.sm)

            if isExpanded, hasExpandableDescription, let description = step.description {
                VStack(alignment: .leading, spacing: JoolsSpacing.xs) {
                    Text(description)
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, JoolsSpacing.xl + JoolsSpacing.md)
                .padding(.trailing, JoolsSpacing.md)
                .padding(.bottom, JoolsSpacing.sm)
            }
        }
    }
}

// MARK: - Step Number Badge

struct StepNumberBadge: View {
    let number: Int
    let status: StepStatus

    var body: some View {
        ZStack {
            Circle()
                .fill(status.backgroundColor)
                .frame(width: 28, height: 28)

            if status == .completed {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(status.foregroundColor)
            } else if status == .inProgress {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(status.foregroundColor)
            }
        }
    }
}

// MARK: - Step Status

enum StepStatus {
    case pending
    case inProgress
    case completed

    var backgroundColor: Color {
        switch self {
        case .pending: return Color.joolsSurface
        case .inProgress: return Color.joolsAccent.opacity(0.15)
        case .completed: return Color.joolsSuccess.opacity(0.15)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .pending: return .secondary
        case .inProgress: return Color.joolsAccent
        case .completed: return Color.joolsSuccess
        }
    }
}

// MARK: - Preview

#Preview("Plan Card with Steps") {
    VStack {
        PlanCardView(
            activity: ActivityEntity(
                id: "preview",
                type: .planGenerated,
                createdAt: Date(),
                contentJSON: try! JSONEncoder().encode(
                    ActivityContentDTO.preview
                )
            ),
            onApprove: {},
            onRevise: {}
        )
    }
    .padding()
    .background(Color.joolsBackground)
}

// MARK: - Preview Helpers

extension ActivityContentDTO {
    static var preview: ActivityContentDTO {
        // Create a simple preview manually
        let json = """
        {
            "plan": {
                "steps": [
                    {"description": "Draft the Comprehensive Requirements Document", "status": "completed"},
                    {"description": "Create the Interactive HTML Mock", "status": "in_progress"},
                    {"description": "Create Static Flow Mocks", "status": "pending"},
                    {"description": "Verify and Refine", "status": "pending"},
                    {"description": "Complete pre-submit steps", "status": "pending"},
                    {"description": "Submit", "status": "pending"}
                ]
            }
        }
        """
        return try! JSONDecoder().decode(ActivityContentDTO.self, from: json.data(using: .utf8)!)
    }
}
