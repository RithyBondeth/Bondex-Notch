import AppKit
import SwiftUI

/// Hook setup for the agent indicator.
///
/// Process presence works without setup. Hooks add the exact live state and
/// "Needs you". For Claude Code, Codex and Gemini, Bondex writes the hook
/// itself and checks it each time this opens, because a setup from an older
/// version, or one left pointing at a copy of the app that has since moved,
/// fails silently. Other agents get the explicit commands to wire by hand.
struct AgentSetupHelp: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var agents: AgentActivityService

    @State private var copied: AgentKind?
    @State private var states: [AgentKind: AgentHookSetup.State] = [:]
    @State private var results: [AgentKind: Result] = [:]

    private struct Result: Equatable {
        let message: String
        let isError: Bool
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        self.agents = environment.agents
        // Read up front, so the first frame is right rather than showing
        // "Not set up" until the files have been looked at.
        _states = State(initialValue: Self.currentStates())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("""
            Running agents appear automatically. Hooks add detailed live \
            statuses such as Thinking, Editing, and Running tests — and show \
            when an agent stops to wait for you: a permission prompt, a \
            question, or a plan to approve.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            ForEach(AgentKind.known) { kind in
                if let setup = setup(for: kind) {
                    managedRow(kind, setup: setup)
                } else {
                    manualRow(kind)
                }
            }
        }
        .onAppear(perform: refresh)
        // Picks up an edit made in an editor, or by the agent itself, while
        // Settings sat in the background.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    // MARK: Rows

    private func header(_ kind: AgentKind) -> some View {
        HStack(spacing: 6) {
            PixelMark(kind: kind)
                .frame(width: 13, height: 13)
            Text(kind.displayName)
                .font(.callout.weight(.semibold))

            if agents.installed.contains(kind) {
                Text("running")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            }
            if agents.active.contains(where: { $0.kind == kind && $0.isHookReported }) {
                Text("working now")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(kind.tint)
            }
        }
    }

    private func managedRow(_ kind: AgentKind, setup: AgentHookSetup) -> some View {
        let state = states[kind] ?? .notSetUp
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                header(kind)
                Spacer()
                if let action = primaryAction(for: state) {
                    Button(action) { install(kind, setup: setup) }
                        .font(.caption)
                        .help("Writes Bondex's hook into \(setup.target.displayPath). The original is kept as a backup.")
                }
                Menu {
                    Button("Copy Command") { copy(kind, setup.command) }
                    Button("Show in Finder") { reveal(setup.target) }
                        .disabled(state == .agentMissing)
                    if state.hasBondexHooks {
                        Divider()
                        Button("Remove Bondex Hooks") { remove(kind, setup: setup) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More options for \(kind.displayName) hooks")
            }

            statusLine(state, setup: setup)

            if let result = results[kind] {
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(result.isError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .unreadable = state {
                commandBlock(setup.command, hint: hint(for: setup.target))
            }
        }
    }

    private func manualRow(_ kind: AgentKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                header(kind)
                Spacer()
                Button(copied == kind ? "Copied" : "Copy commands") { copy(kind, manualCommands(for: kind)) }
                    .font(.caption)
            }
            commandBlock(manualCommands(for: kind), hint: nil)
        }
    }

    private func commandBlock(_ text: String, hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            if let hint {
                Text(hint)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func statusLine(_ state: AgentHookSetup.State, setup: AgentHookSetup) -> some View {
        let path = setup.target.displayPath
        switch state {
        case .ready:
            Label("Set up in \(path)", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .notSetUp:
            Text("Not set up. Adds one hook per event to \(path).")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .incomplete(let missing):
            Label(
                "Missing \(Self.list(missing)), so the notch can't see those moments.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        case .otherCopy(let other):
            Label(
                FileManager.default.fileExists(atPath: other)
                    ? "Runs another copy of Bondex Notch, at \(other)."
                    : "Runs a copy of Bondex Notch that is no longer there, so nothing reaches the notch.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        case .unreadable(let reason):
            Label(
                "\(path) can't be edited safely (\(reason)). Add the hook by hand:",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        case .agentMissing:
            Text("Not found on this Mac.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func primaryAction(for state: AgentHookSetup.State) -> String? {
        switch state {
        case .notSetUp: return "Set Up"
        case .incomplete: return "Update"
        case .otherCopy: return "Use This Copy"
        case .ready, .unreadable, .agentMissing: return nil
        }
    }

    // MARK: Actions

    private func setup(for kind: AgentKind) -> AgentHookSetup? {
        AgentHookSetup.Target.standard(for: kind).map { AgentHookSetup(target: $0) }
    }

    private static func currentStates() -> [AgentKind: AgentHookSetup.State] {
        var states: [AgentKind: AgentHookSetup.State] = [:]
        for kind in AgentKind.known {
            if let target = AgentHookSetup.Target.standard(for: kind) {
                states[kind] = AgentHookSetup(target: target).state()
            }
        }
        return states
    }

    private func refresh() {
        states = Self.currentStates()
    }

    private func install(_ kind: AgentKind, setup: AgentHookSetup) {
        perform(kind) {
            let change = try setup.install()
            guard case .updated(let added, let repointed, _, let backup) = change else {
                return "Already set up."
            }
            var parts: [String] = []
            if !added.isEmpty { parts.append("Added \(Self.list(added))") }
            if repointed > 0 { parts.append("pointed \(Self.count(repointed, "hook")) at this copy") }
            var message = parts.joined(separator: " and ").capitalizedFirst + "."
            message += setup.target.asksToTrustChanges
                ? " \(kind.displayName) asks you to review new or changed hooks before they run."
                : " New \(kind.displayName) sessions will use them."
            if let backup { message += " The original is kept as \(backup.lastPathComponent)." }
            return message
        }
    }

    private func remove(_ kind: AgentKind, setup: AgentHookSetup) {
        perform(kind) {
            let change = try setup.remove()
            guard case .updated(_, _, let removed, let backup) = change else {
                return "There were no Bondex hooks to remove."
            }
            var message = "Removed \(Self.count(removed, "hook"))."
            if let backup { message += " The original is kept as \(backup.lastPathComponent)." }
            return message
        }
    }

    private func perform(_ kind: AgentKind, _ action: () throws -> String) {
        do {
            results[kind] = Result(message: try action(), isError: false)
        } catch {
            results[kind] = Result(message: error.localizedDescription, isError: true)
        }
        refresh()
    }

    private func reveal(_ target: AgentHookSetup.Target) {
        if FileManager.default.fileExists(atPath: target.file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([target.file])
        } else {
            NSWorkspace.shared.open(target.agentDirectory)
        }
    }

    private func copy(_ kind: AgentKind, _ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = kind
        // Reverts the label so the button does not read "Copied" forever, which
        // makes a second copy look like it did nothing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copied == kind { copied = nil }
        }
    }

    // MARK: Text

    private func hint(for target: AgentHookSetup.Target) -> String {
        "\(target.displayPath) → hooks.\(target.events.joined(separator: " / "))"
    }

    /// The explicit busy/attention/idle calls, for agents that do not pass
    /// their events as JSON.
    private func manualCommands(for kind: AgentKind) -> String {
        let binary = AgentHookSetup.currentBinaryPath
        return """
        "\(binary)" --agent-busy \(kind.id) "optional status"
        "\(binary)" --agent-attention \(kind.id) "what it needs"
        "\(binary)" --agent-idle \(kind.id)
        """
    }

    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
