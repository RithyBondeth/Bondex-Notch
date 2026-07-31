import Foundation
import XCTest
@testable import BondexNotch

/// The one rule that keeps this feature from misfiring: the Claude *desktop app*
/// must never be mistaken for Claude Code. They differ only by the case of the
/// executable name, which makes a careless `lowercased()` a real risk.
final class AgentDetectionTests: XCTestCase {

    func testClaudeCodeIsRecognisedFromItsRealInstallPath() {
        // Verbatim from a live install.
        let path = "/Users/x/Library/Application Support/Claude/claude-code/2.1.219/claude.app/Contents/MacOS/claude"
        XCTAssertEqual(AgentActivityService.agentKind(forExecutablePath: path), .claude)
    }

    func testCodexIsRecognisedFromItsRealInstallPath() {
        let path = "/Users/x/.cursor/extensions/openai.chatgpt-26.721.30844-darwin-arm64/bin/macos-aarch64/codex"
        XCTAssertEqual(AgentActivityService.agentKind(forExecutablePath: path), .codex)
    }

    func testTheClaudeDesktopAppIsNotACodingAgent() {
        // Capital C. Matching case-insensitively would light the notch up for
        // every minute the desktop app is open.
        XCTAssertNil(
            AgentActivityService.agentKind(
                forExecutablePath: "/Applications/Claude.app/Contents/MacOS/Claude"
            )
        )
        XCTAssertNil(
            AgentActivityService.agentKind(
                forExecutablePath: "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper"
            )
        )
    }

    func testUnrelatedBinariesAreIgnored() {
        for path in ["/usr/bin/node", "/bin/zsh", "/usr/local/bin/claudia", "/opt/homebrew/bin/codexify"] {
            XCTAssertNil(AgentActivityService.agentKind(forExecutablePath: path), path)
        }
    }
}

/// The command an agent's hook actually runs.
final class AgentSignalCommandTests: XCTestCase {

    func testBusyIsParsedWithAStatus() {
        let command = AgentSignalCommand.parse(
            ["BondexNotch", "--agent-busy", "claude", "Editing", "PeekView.swift"]
        )
        guard case .busy(let kind, let status) = command else {
            return XCTFail("expected a busy command, got \(String(describing: command))")
        }
        XCTAssertEqual(kind, .claude)
        // Everything after the agent name is the status, so a hook can pass an
        // unquoted tool name without it being dropped.
        XCTAssertEqual(status, "Editing PeekView.swift")
    }

    func testBusyWithoutAStatusCarriesNone() {
        guard case .busy(let kind, let status) = AgentSignalCommand.parse(
            ["BondexNotch", "--agent-busy", "codex"]
        ) else {
            return XCTFail("expected a busy command")
        }
        XCTAssertEqual(kind, .codex)
        XCTAssertNil(status, "an empty status must not render as a blank line")
    }

    func testIdleIsParsed() {
        guard case .idle(let kind) = AgentSignalCommand.parse(
            ["BondexNotch", "--agent-idle", "Claude"]
        ) else {
            return XCTFail("expected an idle command")
        }
        // Case-insensitive on the *argument*, unlike executable matching: this is
        // something a human typed into a config file.
        XCTAssertEqual(kind, .claude)
    }

    func testUnknownAgentsAndOtherFlagsAreNotCommands() {
        XCTAssertNil(AgentSignalCommand.parse(["BondexNotch"]))
        XCTAssertNil(AgentSignalCommand.parse(["BondexNotch", "--agent-busy"]))
        XCTAssertNil(AgentSignalCommand.parse(["BondexNotch", "--agent-busy", "copilot"]))
        XCTAssertNil(AgentSignalCommand.parse(["BondexNotch", "--render-previews", "/tmp"]))
    }
}

final class AgentActivityModelTests: XCTestCase {

    func testElapsedNeverRunsBackwards() {
        // Clock changes and NTP steps are real; a negative duration would format
        // as nonsense in the peek.
        let activity = AgentActivity(kind: .claude, startedAt: Date().addingTimeInterval(60), status: nil)
        XCTAssertEqual(activity.elapsed(), 0)
    }

    func testElapsedFormatsAsAClock() {
        let started = Date().addingTimeInterval(-125)
        let activity = AgentActivity(kind: .claude, startedAt: started, status: nil)
        XCTAssertEqual(activity.elapsed().clockString, "2:05")
    }

    /// The staleness backstop only has to catch an agent that was killed without
    /// its `Stop` hook running. It must be long enough to sit through a single
    /// slow tool call — a test suite or a build — without blinking out.
    func testTheStalenessBackstopOutlastsALongToolCall() {
        XCTAssertGreaterThanOrEqual(AgentActivityService.staleAfter, 60)
    }

    func testTheSignalDirectoryIsUnderTheHomeDirectory() {
        XCTAssertTrue(
            AgentActivityService.signalDirectory.path.hasPrefix(NSHomeDirectory()),
            "hooks run as the user, so the signal has to live somewhere they can write"
        )
    }
}

/// Round-trips the signal through the real filesystem, which is what the CLI and
/// the watcher actually share.
final class AgentSignalFileTests: XCTestCase {

    override func tearDown() {
        try? AgentActivityService.markIdle(.codex)
        super.tearDown()
    }

    func testBusyThenIdleRoundTrips() throws {
        try AgentActivityService.markBusy(.codex, status: "Running tests")

        let signal = try XCTUnwrap(AgentActivityService.readSignal(for: .codex))
        XCTAssertEqual(signal.status, "Running tests")
        XCTAssertLessThan(abs(signal.date.timeIntervalSinceNow), 5)

        try AgentActivityService.markIdle(.codex)
        XCTAssertNil(AgentActivityService.readSignal(for: .codex))
    }

    /// A second `--agent-busy` is the heartbeat, and it has to move the file's
    /// date or the staleness backstop would expire a working agent.
    func testASecondBusyRefreshesTheHeartbeat() throws {
        try AgentActivityService.markBusy(.codex, status: nil)
        let first = try XCTUnwrap(AgentActivityService.readSignal(for: .codex)).date

        Thread.sleep(forTimeInterval: 1.1)
        try AgentActivityService.markBusy(.codex, status: nil)
        let second = try XCTUnwrap(AgentActivityService.readSignal(for: .codex)).date

        XCTAssertGreaterThan(second, first)
    }

    func testAStatusIsClampedToOneShortLine() throws {
        try AgentActivityService.markBusy(
            .codex,
            status: String(repeating: "x", count: 400) + "\nsecond line"
        )
        let status = try XCTUnwrap(AgentActivityService.readSignal(for: .codex)).status
        // The peek is one strip beside the notch; anything longer is not a status
        // but a paragraph, and the second line would never be seen anyway.
        XCTAssertEqual(status?.count, 60)
    }

    func testIdleOnAnAgentThatWasNeverBusyIsNotAnError() {
        XCTAssertNoThrow(try AgentActivityService.markIdle(.codex))
    }
}


/// The mark is drawn from a grid of strings, which is easy to get subtly wrong
/// in ways no compiler catches: a short row, a mirrored layout, or a path built
/// upside down because layer geometry has its origin at the bottom.
final class PixelMarkTests: XCTestCase {

    func testClaudesMarkIsARectangularGrid() throws {
        let mark = try XCTUnwrap(AgentKind.claude.pixelMark)
        XCTAssertTrue(
            mark.allSatisfy { $0.count == 16 },
            "a short row shifts every cell after it and silently skews the mark"
        )
        XCTAssertEqual(mark.count, 10)
    }

    /// The mark is symmetric, so a mirrored row is the one error that still
    /// looks plausible in the source.
    func testClaudesMarkIsHorizontallySymmetric() throws {
        let mark = try XCTUnwrap(AgentKind.claude.pixelMark)
        for (index, row) in mark.enumerated() {
            XCTAssertEqual(row, String(row.reversed()), "row \(index) is not symmetric")
        }
    }

    func testTheGridBecomesOneRectPerFilledCell() throws {
        let mark = ["X.", ".X"]
        let path = AgentOrbView.path(for: mark, in: CGRect(x: 0, y: 0, width: 2, height: 2))
        XCTAssertFalse(path.isEmpty)

        // Row 0 is the *top* row, and layer geometry counts up from the bottom,
        // so the first row's cell must land in the upper half.
        var rects: [CGRect] = []
        path.applyWithBlock { element in
            if element.pointee.type == .moveToPoint {
                rects.append(CGRect(origin: element.pointee.points[0], size: .zero))
            }
        }
        XCTAssertEqual(rects.count, 2)
        let topLeft = try XCTUnwrap(rects.first { $0.origin.x == 0 })
        XCTAssertEqual(topLeft.origin.y, 1, "the first row must be drawn at the top")
    }

    func testAnEmptyGridIsNotACrash() {
        XCTAssertTrue(
            AgentOrbView.path(for: [], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty
        )
        XCTAssertTrue(
            AgentOrbView.path(for: ["XX"], in: .zero).isEmpty
        )
    }
}
