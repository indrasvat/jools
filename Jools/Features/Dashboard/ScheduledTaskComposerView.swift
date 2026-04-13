import SwiftUI
import UIKit

struct ScheduledTaskComposerView: View {
    let source: SourceEntity
    let template: ScheduledSkillTemplate

    @Environment(\.dismiss) private var dismiss

    @State private var cadence: ScheduleCadence = .daily
    @State private var selectedBranch: String = "main"
    @State private var runTime: Date = Calendar.current.date(
        bySettingHour: 13,
        minute: 0,
        second: 0,
        of: .now
    ) ?? .now
    @State private var showPromptDetails = false
    @State private var copiedPrompt = false
    @State private var showWebContinuation = false
    @State private var showReturnSheet = false
    @State private var didOpenContinuation = false

    private let suggestedBranches = ["main", "master", "develop"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JoolsSpacing.lg) {
                    roleCard
                    scheduleCard
                    handoffCard
                    MadeWithJoolsFooter()
                }
                .padding()
            }
            .background(Color.joolsBackground)
            .navigationTitle("Scheduled Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .fullScreenCover(
            isPresented: $showWebContinuation,
            onDismiss: handleContinuationDismiss
        ) {
            SafariView(url: continuationURL)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showReturnSheet) {
            ScheduledReturnSheet(
                source: source,
                copiedPrompt: copiedPrompt,
                onDone: {
                    showReturnSheet = false
                    dismiss()
                },
                onCopyAgain: copyPromptToClipboard,
                onOpenAgain: startWebContinuation
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .accessibilityIdentifier("scheduled.composer")
    }

    private var roleCard: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.md) {
            HStack(spacing: JoolsSpacing.sm) {
                Image(systemName: template.icon)
                    .font(.title2)
                    .foregroundStyle(template.accent)
                    .frame(width: 44, height: 44)
                    .background(template.accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.joolsTitle3)
                    Text(template.subtitle)
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(template.cadenceSummary)
                    .font(.joolsCaption)
                    .foregroundStyle(template.accent)
                    .padding(.horizontal, JoolsSpacing.sm)
                    .padding(.vertical, JoolsSpacing.xxs)
                    .background(template.accent.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(template.details)
                .font(.joolsBody)
                .foregroundStyle(.secondary)

            DisclosureGroup("Advanced prompt details", isExpanded: $showPromptDetails) {
                Text(template.prompt)
                    .font(.joolsBody)
                    .foregroundStyle(.primary)
                    .padding(.top, JoolsSpacing.sm)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("scheduled.prompt")
            }
            .font(.joolsBody)
            .tint(.secondary)
        }
        .padding()
        .background(Color.joolsSurface)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.md) {
            Text("Schedule")
                .font(.joolsHeadline)

            Picker("Cadence", selection: $cadence) {
                ForEach(ScheduleCadence.allCases) { cadence in
                    Text(cadence.title).tag(cadence)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .top, spacing: JoolsSpacing.md) {
                VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
                    Text("Time")
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)
                    DatePicker(
                        "",
                        selection: $runTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }

                Spacer()

                VStack(alignment: .trailing, spacing: JoolsSpacing.xxs) {
                    Text("Timezone")
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)
                    Text(TimeZone.current.identifier)
                        .font(.joolsBody)
                        .multilineTextAlignment(.trailing)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
                LabeledContent("Repository") {
                    Text(source.displayName)
                        .foregroundStyle(.primary)
                }
                .font(.joolsBody)

                VStack(alignment: .leading, spacing: JoolsSpacing.xs) {
                    Text("Branch")
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)

                    TextField("Branch", text: $selectedBranch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.joolsBody)
                        .padding(.horizontal, JoolsSpacing.sm)
                        .padding(.vertical, JoolsSpacing.sm)
                        .background(Color.joolsSurfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
                        .accessibilityIdentifier("scheduled.branch")

                    HStack(spacing: JoolsSpacing.xs) {
                        ForEach(suggestedBranches, id: \.self) { branch in
                            BranchSuggestionChip(
                                title: branch,
                                isSelected: branch == selectedBranch
                            ) {
                                selectedBranch = branch
                            }
                        }
                    }
                }
            }

            HStack(spacing: JoolsSpacing.sm) {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundStyle(template.accent)

                Text(scheduleSummary)
                    .font(.joolsBody)
                    .foregroundStyle(.primary)
            }
            .padding()
            .background(template.accent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        }
        .padding()
        .background(Color.joolsSurface)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))
    }

    private var handoffCard: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.md) {
            Label("Continue in Jules", systemImage: "safari")
                .font(.joolsHeadline)

            Text("Jataayu prepares the schedule, branch, and prompt here. Jules web still has to create the recurring task because the public API does not expose scheduled-task creation yet.")
                .font(.joolsBody)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
                ContinuationStep(number: 1, text: "Jataayu opens \(source.repo) directly in Jules web.")
                ContinuationStep(number: 2, text: "The prompt is copied automatically before the handoff.")
                ContinuationStep(number: 3, text: "In Jules, switch to Scheduled, pick \(template.name), and keep the same cadence and branch.")
            }

            if copiedPrompt {
                HStack(spacing: JoolsSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.joolsSuccess)
                    Text("Prompt copied and ready to paste in Jules.")
                        .font(.joolsCaption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: JoolsSpacing.sm) {
                Button(action: startWebContinuation) {
                    Label("Continue in Jules", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.joolsAccent)
                .accessibilityIdentifier("scheduled.continue")

                HStack(spacing: JoolsSpacing.sm) {
                    Button(action: copyPromptToClipboard) {
                        Label(copiedPrompt ? "Copied" : "Copy Prompt", systemImage: copiedPrompt ? "checkmark.circle.fill" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("scheduled.copyPrompt")

                    Link(destination: continuationURL) {
                        Label("Open Repo", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("scheduled.openRepo")
                }
            }

            Text("Opens \(source.displayName) inside an in-app browser so you can return to Jataayu without context switching.")
                .font(.joolsCaption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.joolsSurface)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))
    }

    private var scheduleSummary: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(cadence.title) at \(formatter.string(from: runTime)) on \(selectedBranch)"
    }

    private var continuationURL: URL {
        URL(string: "https://jules.google.com/repo/github/\(source.owner)/\(source.repo)/overview")!
    }

    private func copyPromptToClipboard() {
        UIPasteboard.general.string = template.prompt
        copiedPrompt = true
    }

    private func startWebContinuation() {
        copyPromptToClipboard()
        didOpenContinuation = true
        showWebContinuation = true
    }

    private func handleContinuationDismiss() {
        guard didOpenContinuation else { return }
        didOpenContinuation = false
        showReturnSheet = true
    }
}

private struct BranchSuggestionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.joolsCaption)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, JoolsSpacing.sm)
                .padding(.vertical, JoolsSpacing.xxs)
                .background(isSelected ? Color.joolsAccent : Color.joolsSurfaceElevated)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ContinuationStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: JoolsSpacing.sm) {
            Text("\(number)")
                .font(.joolsCaption.weight(.semibold))
                .foregroundStyle(Color.joolsAccent)
                .frame(width: 22, height: 22)
                .background(Color.joolsAccent.opacity(0.12))
                .clipShape(Circle())

            Text(text)
                .font(.joolsBody)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ScheduledReturnSheet: View {
    let source: SourceEntity
    let copiedPrompt: Bool
    let onDone: () -> Void
    let onCopyAgain: () -> Void
    let onOpenAgain: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: JoolsSpacing.lg) {
                VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
                    Text("Back in Jataayu")
                        .font(.joolsTitle2)
                    Text("If the schedule was created in Jules, you’re done. If not, Jataayu can reopen the repo with the prepared prompt still ready.")
                        .font(.joolsBody)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: JoolsSpacing.sm) {
                    Image(systemName: copiedPrompt ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundStyle(copiedPrompt ? Color.joolsSuccess : Color.joolsAccent)
                    Text(copiedPrompt ? "Prompt is still copied for \(source.repo)." : "Prompt is ready to copy again.")
                        .font(.joolsBody)
                }
                .padding()
                .background(Color.joolsSurface)
                .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))

                VStack(spacing: JoolsSpacing.sm) {
                    Button("Done", action: onDone)
                        .buttonStyle(.borderedProminent)
                        .tint(.joolsAccent)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("scheduled.return.done")

                    HStack(spacing: JoolsSpacing.sm) {
                        Button("Copy Again", action: onCopyAgain)
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("scheduled.return.copyAgain")

                        Button("Open Jules Again", action: onOpenAgain)
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("scheduled.return.openAgain")
                    }
                }

                Spacer()
            }
            .padding()
            .background(Color.joolsBackground)
        }
    }
}
