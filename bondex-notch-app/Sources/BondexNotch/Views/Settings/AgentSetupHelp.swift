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

            ForEach(AgentKind.allCases) { kind in
                agentRow(kind)
            }
        }
    }

    private func agentRow(_ kind: AgentKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: kind.systemImage)
                    .foregroundStyle(kind.tint)
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
        }
    }

    /// The two calls a hook makes. Deliberately shown as plain commands rather
    /// than as a finished config block: the shape of hook configuration differs
    /// between agents and changes between versions, while these two lines are
    /// the part that is actually ours and will not.
    private func commands(for kind: AgentKind) -> String {
        let binary = Bundle.main.executableURL?.path ?? "/Applications/Bondex Notch.app/Contents/MacOS/BondexNotch"
        return """
        "\(binary)" --agent-busy \(kind.rawValue) "optional status"
        "\(binary)" --agent-idle \(kind.rawValue)
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
