import AppKit
import SwiftUI

/// Setup instructions for the agent indicator.
///
/// This exists because the feature genuinely cannot work without one
/// configuration step, and a toggle that silently does nothing until you find
/// the documentation is worse than no toggle. The exact hook block is shown and
/// copyable, with the binary's real path already filled in — the most common way
/// to get this wrong is pointing a hook at a Bondex that has since moved.
struct AgentSetupHelp: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var agents: AgentActivityService

    @State private var copied: AgentKind?

    init(environment: AppEnvironment) {
        self.environment = environment
        self.agents = environment.agents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("""
            An agent that is "working" is almost always waiting — on the model, \
            or on a tool. It burns no measurable CPU, so there is nothing to \
            detect from the outside. Instead the agent says so itself, through \
            one hook:
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            ForEach(AgentKind.known) { kind in
                agentRow(kind)
            }
        }
    }

    private func agentRow(_ kind: AgentKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
                if agents.active.contains(where: { $0.kind == kind }) {
                    Text("working now")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(kind.tint)
                }

                Spacer()

                Button(copied == kind ? "Copied" : "Copy commands") { copy(kind) }
                    .font(.caption)
            }

            Text(commands(for: kind))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            // Where the two lines go. Every agent puts its hooks somewhere
            // different, and names the same two moments differently, so the
            // commands on their own leave the harder half unanswered.
            if let hint = kind.hookConfigHint {
                Text(hint)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// The calls a hook makes. Codex supplies documented JSON on stdin, so one
    /// command can choose busy/idle and turn tool input into a useful status.
    /// Other agents keep the portable explicit busy/idle pair.
    private func commands(for kind: AgentKind) -> String {
        let binary = Bundle.main.executableURL?.path ?? "/Applications/Bondex Notch.app/Contents/MacOS/BondexNotch"
        if kind.id == AgentKind.codex.id {
            return "\"\(binary)\" --agent-hook codex"
        }
        return """
        "\(binary)" --agent-busy \(kind.id) "optional status"
        "\(binary)" --agent-idle \(kind.id)
        """
    }

    private func copy(_ kind: AgentKind) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commands(for: kind), forType: .string)
        copied = kind
        // Reverts the label so the button does not read "Copied" forever, which
        // makes a second copy look like it did nothing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copied == kind { copied = nil }
        }
    }
}
