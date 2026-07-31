import AppKit
import SwiftUI

/// What the working copy you are in the middle of looks like right now.
///
/// The question this answers is the one you ask by running `git status` for the
/// fortieth time in an afternoon: which branch, how far from the remote, what is
/// uncommitted. Everything here is read-only — the notch is a place to *see* the
/// repository, not to act on it, and a stray click that staged or discarded
/// something from a panel that opens on hover would be indefensible.
struct DevWidget: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var service: DevProjectService
    @ObservedObject private var notch: NotchViewModel
    @ObservedObject private var settings: SettingsStore

    init(environment: AppEnvironment) {
        self.environment = environment
        self.service = environment.dev
        self.notch = environment.notch
        self.settings = environment.settings
    }

    private var accent: Color { settings.effectiveAccent.color }

    var body: some View {
        Group {
            if let snapshot = service.snapshot {
                repository(snapshot)
            } else if let problem = service.problem {
                unavailable(problem)
            } else {
                EmptyStateView(systemImage: "arrow.triangle.branch", title: "Reading the repository…")
                    .frame(maxHeight: .infinity)
            }
        }
        // An edit to a tracked file changes the file, not `.git`, so the watcher
        // never hears about it. Opening the panel is the moment the answer has to
        // be current, and it is also the only moment anyone is looking.
        .onAppear { service.refresh() }
        .animation(Motion.content(settings.motion), value: service.snapshot)
    }

    // MARK: Repository

    private func repository(_ snapshot: DevSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(snapshot)
            lastCommit(snapshot)
            changes(snapshot)
        }
    }

    private func header(_ snapshot: DevSnapshot) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: snapshot.isDetached ? "point.3.connected.trianglepath.dotted" : "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                // Middle truncation, because a long branch name is almost always
                // `type/what-it-is` and both halves carry meaning — cutting the
                // end off leaves a row of identically-prefixed names.
                Text(snapshot.branch)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            // Hugs the name rather than reserving a fixed column: a fixed width
            // strands the sync badges in the middle of the row on every branch
            // whose name is shorter than the column.
            .layoutPriority(1)

            if snapshot.ahead > 0 {
                syncBadge(systemImage: "arrow.up", count: snapshot.ahead, tint: accent)
            }
            if snapshot.behind > 0 {
                syncBadge(
                    systemImage: "arrow.down",
                    count: snapshot.behind,
                    tint: Color(red: 0.99, green: 0.72, blue: 0.25)
                )
            }
            // Nothing to say about the remote is worth saying explicitly: a
            // branch that has never been pushed looks identical to one that is
            // in sync unless the difference is named.
            if snapshot.upstream == nil, !snapshot.isDetached {
                Text("no upstream")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
            }

            Spacer(minLength: 4)

            if let operation = snapshot.operation {
                Text(operation)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(red: 0.99, green: 0.72, blue: 0.25))
                    )
            }

            if let name = service.projectName {
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private func syncBadge(systemImage: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .bold))
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(tint)
    }

    @ViewBuilder
    private func lastCommit(_ snapshot: DevSnapshot) -> some View {
        if let subject = snapshot.lastCommitSubject {
            HStack(spacing: 7) {
                Text(snapshot.lastCommitHash ?? "")
                    .font(.system(size: 10, weight: .semibold).monospaced())
                    .foregroundStyle(accent)
                Text(subject)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let date = snapshot.lastCommitDate {
                    Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .notchCard(padding: Theme.compactCardPadding)
        }
    }

    @ViewBuilder
    private func changes(_ snapshot: DevSnapshot) -> some View {
        if snapshot.isClean {
            EmptyStateView(
                systemImage: "checkmark.seal",
                title: "Working tree clean",
                subtitle: snapshot.ahead > 0
                    ? "\(snapshot.ahead) commit\(snapshot.ahead == 1 ? "" : "s") to push"
                    : nil
            )
            .frame(maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                counts(snapshot)
                ScrollingStack(spacing: 3) {
                    ForEach(snapshot.changes) { change in
                        row(change)
                    }
                }
            }
        }
    }

    private func counts(_ snapshot: DevSnapshot) -> some View {
        HStack(spacing: 10) {
            if snapshot.conflictCount > 0 {
                countLabel("\(snapshot.conflictCount) conflicted",
                           tint: Color(red: 0.98, green: 0.35, blue: 0.35))
            }
            if snapshot.stagedCount > 0 {
                countLabel("\(snapshot.stagedCount) staged",
                           tint: Color(red: 0.32, green: 0.80, blue: 0.55))
            }
            if snapshot.modifiedCount > 0 {
                countLabel("\(snapshot.modifiedCount) modified", tint: accent)
            }
            if snapshot.untrackedCount > 0 {
                countLabel("\(snapshot.untrackedCount) untracked", tint: Theme.tertiaryText)
            }
            Spacer(minLength: 0)
        }
    }

    private func countLabel(_ text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func row(_ change: DevChange) -> some View {
        HStack(spacing: 7) {
            Text(change.kind.glyph)
                .font(.system(size: 9, weight: .bold).monospaced())
                .foregroundStyle(tint(for: change.kind))
                .frame(width: 13, height: 13)
                .background(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(tint(for: change.kind).opacity(0.16))
                )

            // The directory is dimmed rather than dropped: two files called
            // `View.swift` in different folders are otherwise the same row twice.
            Text(change.directory)
                .foregroundStyle(Theme.tertiaryText)
                + Text(change.name)
                .foregroundStyle(Theme.primaryText)

            Spacer(minLength: 0)
        }
        .font(.system(size: 10.5))
        .lineLimit(1)
        .truncationMode(.head)
    }

    private func tint(for kind: DevChange.Kind) -> Color {
        switch kind {
        case .conflicted: return Color(red: 0.98, green: 0.35, blue: 0.35)
        case .staged: return Color(red: 0.32, green: 0.80, blue: 0.55)
        case .modified: return accent
        case .untracked: return Theme.secondaryText
        }
    }

    // MARK: Unavailable

    private func unavailable(_ problem: DevProjectProblem) -> some View {
        VStack(spacing: 8) {
            EmptyStateView(
                systemImage: problem.systemImage,
                title: problem.title,
                subtitle: problem.detail
            )
            if problem == .noFolderChosen {
                Button("Choose Project Folder…") { chooseFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule(style: .continuous).fill(accent))
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Also offered here, not only in Settings: being told to go and configure
    /// something elsewhere, by a panel that is about to close as soon as the
    /// pointer leaves it, is a dead end.
    private func chooseFolder() {
        notch.setPinned(true)
        guard let path = DevProjectPicker.choose() else {
            notch.setPinned(false)
            return
        }
        settings.preferences.devProjectPath = path
        notch.setPinned(false)
    }
}

/// The open panel, shared by the widget and Settings.
enum DevProjectPicker {
    @MainActor
    static func choose(startingAt current: String = "") -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a Git working copy for the Dev tab."
        if !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: current, isDirectory: true)
        }
        // The notch panel is non-activating, so without this the open panel can
        // come up behind whatever the user was actually looking at.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
