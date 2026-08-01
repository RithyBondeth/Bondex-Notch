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
        guard case .command(.busy(let kind, let status)) = command else {
            return XCTFail("expected a busy command, got \(String(describing: command))")
        }
        XCTAssertEqual(kind, .claude)
        // Everything after the agent name is the status, so a hook can pass an
        // unquoted tool name without it being dropped.
        XCTAssertEqual(status, "Editing PeekView.swift")
    }

    func testBusyWithoutAStatusCarriesNone() {
        guard case .command(.busy(let kind, let status)) = AgentSignalCommand.parse(
            ["BondexNotch", "--agent-busy", "codex"]
        ) else {
            return XCTFail("expected a busy command")
        }
        XCTAssertEqual(kind, .codex)
        XCTAssertNil(status, "an empty status must not render as a blank line")
    }

    func testIdleIsParsed() {
        guard case .command(.idle(let kind)) = AgentSignalCommand.parse(
            ["BondexNotch", "--agent-idle", "Claude"]
        ) else {
            return XCTFail("expected an idle command")
        }
        // Case-insensitive on the *argument*, unlike executable matching: this is
        // something a human typed into a config file.
        XCTAssertEqual(kind, .claude)
    }

    func testHookModeIsParsed() {
        XCTAssertEqual(
            AgentSignalCommand.parse(["BondexNotch", "--agent-hook", "codex"]),
            .command(.hook(.codex))
        )
    }

    /// An agent Bondex ships no artwork for still gets to report itself, rather
    /// than needing a release before it can light the notch at all.
    func testAnAgentWithNoBuiltInSupportIsStillAccepted() {
        guard case .command(.busy(let kind, _)) = AgentSignalCommand.parse(
            ["BondexNotch", "--agent-busy", "aider", "Refactoring"]
        ) else {
            return XCTFail("expected a busy command")
        }
        XCTAssertEqual(kind.id, "aider")
        XCTAssertFalse(kind.isKnown)
        XCTAssertEqual(kind.displayName, "Aider", "an unknown name still has to read as a name")
    }

    func testFlagsThatAreNotAgentSignalsLeaveTheAppToStartNormally() {
        XCTAssertEqual(AgentSignalCommand.parse(["BondexNotch"]), .none)
        XCTAssertEqual(AgentSignalCommand.parse(["BondexNotch", "--render-previews", "/tmp"]), .none)
    }

    /// The bug this replaced: `parse` returned nil for a malformed agent flag
    /// exactly as it did for "no agent flag here", so `main` fell through and
    /// launched the *app*. A hook fires dozens of times a turn, so that was a
    /// duplicate panel per tool call, none of which ever exited.
    func testAMalformedAgentFlagIsAnErrorRatherThanASilentAppLaunch() {
        for arguments in [
            ["BondexNotch", "--agent-busy"],                     // no name at all
            ["BondexNotch", "--agent-idle"],
            ["BondexNotch", "--agent-busy", "cla ude"],          // not a plain name
            ["BondexNotch", "--agent-busy", "clau/de"]
        ] {
            guard case .invalid = AgentSignalCommand.parse(arguments) else {
                return XCTFail("expected \(arguments) to be rejected outright")
            }
        }
    }

    /// The name becomes a path component, so this is a containment check, not a
    /// tidiness one.
    func testAnAgentNameCannotEscapeTheSignalDirectory() {
        for name in ["../../../etc/passwd", "..", "/absolute", "a/b", ""] {
            XCTAssertNil(AgentKind(name: name), "\(name) must not become a signal file")
        }
    }
}

final class AgentHookInputTests: XCTestCase {
    func testCodexBashPayloadShowsTheCommand() throws {
        let data = try payload(
            event: "PreToolUse",
            tool: "Bash",
            input: ["command": "swift test\nsecond command"]
        )
        XCTAssertEqual(
            AgentHookInput.action(from: data),
            .busy(status: "Running swift test")
        )
    }

    func testApplyPatchNamesTheFileBeingEdited() throws {
        let data = try payload(
            event: "PreToolUse",
            tool: "apply_patch",
            input: ["command": "*** Begin Patch\n*** Update File: /tmp/PeekView.swift\n"]
        )
        XCTAssertEqual(
            AgentHookInput.action(from: data),
            .busy(status: "Editing PeekView.swift")
        )
    }

    func testMCPToolGetsAReadableFallback() throws {
        let data = try payload(
            event: "PreToolUse",
            tool: "mcp__Claude_Browser__computer",
            input: [:]
        )
        XCTAssertEqual(
            AgentHookInput.action(from: data),
            .busy(status: "Using computer")
        )
    }

    func testStopClearsTheAgent() throws {
        XCTAssertEqual(
            AgentHookInput.action(from: try payload(event: "Stop")),
            .idle
        )
    }

    func testMalformedAndUnrelatedEventsAreIgnored() throws {
        XCTAssertEqual(AgentHookInput.action(from: Data("nope".utf8)), .ignore)
        XCTAssertEqual(
            AgentHookInput.action(from: try payload(event: "SessionStart")),
            .ignore
        )
    }

    private func payload(
        event: String,
        tool: String? = nil,
        input: [String: Any] = [:]
    ) throws -> Data {
        var object: [String: Any] = ["hook_event_name": event]
        if let tool {
            object["tool_name"] = tool
            object["tool_input"] = input
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}

@MainActor
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

    /// A made-up name, for the reason spelled out in `ConcurrentAgentTests`:
    /// this writes to the live signal directory, so using `.codex` here would
    /// delete a real Codex run's signal on tearDown.
    private let agent = AgentKind(name: "bondex-test-signal")!

    override func tearDown() {
        try? AgentActivityService.markIdle(agent)
        super.tearDown()
    }

    func testBusyThenIdleRoundTrips() throws {
        try AgentActivityService.markBusy(agent, status: "Running tests")

        let signal = try XCTUnwrap(AgentActivityService.readSignal(for: agent))
        XCTAssertEqual(signal.status, "Running tests")
        XCTAssertLessThan(abs(signal.date.timeIntervalSinceNow), 5)

        try AgentActivityService.markIdle(agent)
        XCTAssertNil(AgentActivityService.readSignal(for: agent))
    }

    /// A second `--agent-busy` is the heartbeat, and it has to move the file's
    /// date or the staleness backstop would expire a working agent.
    func testASecondBusyRefreshesTheHeartbeat() throws {
        try AgentActivityService.markBusy(agent, status: nil)
        let first = try XCTUnwrap(AgentActivityService.readSignal(for: agent)).date

        Thread.sleep(forTimeInterval: 1.1)
        try AgentActivityService.markBusy(agent, status: nil)
        let second = try XCTUnwrap(AgentActivityService.readSignal(for: agent)).date

        XCTAssertGreaterThan(second, first)
    }

    func testAStatusIsClampedToOneShortLine() throws {
        try AgentActivityService.markBusy(
            agent,
            status: String(repeating: "x", count: 400) + "\nsecond line"
        )
        let status = try XCTUnwrap(AgentActivityService.readSignal(for: agent)).status
        // The peek is one strip beside the notch; anything longer is not a status
        // but a paragraph, and the second line would never be seen anyway.
        XCTAssertEqual(status?.count, 60)
    }

    func testIdleOnAnAgentThatWasNeverBusyIsNotAnError() {
        XCTAssertNoThrow(try AgentActivityService.markIdle(agent))
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

/// The drawn marks. A mark that silently produces nothing looks exactly like an
/// agent that is not running, which is the failure this is here to catch.
final class AgentMarkTests: XCTestCase {

    private let box = CGRect(x: 0, y: 0, width: 32, height: 32)

    func testEveryKnownAgentDrawsSomething() {
        for kind in AgentKind.known {
            XCTAssertFalse(
                AgentMarks.path(for: kind, in: box).isEmpty,
                "\(kind.id) draws an empty mark, which renders as no agent at all"
            )
        }
    }

    /// Unknown agents fall back to the generic mark rather than to nothing.
    func testAnUnknownAgentStillDrawsAMark() throws {
        let kind = try XCTUnwrap(AgentKind(name: "aider"))
        XCTAssertFalse(AgentMarks.path(for: kind, in: box).isEmpty)
    }

    /// Each mark has to stay inside the box it is given: the orb positions the
    /// glyph layer by its bounds, so a path that overflows is drawn clipped or
    /// off-centre rather than scaled to fit.
    func testMarksStayInsideTheirBox() {
        for kind in AgentKind.known {
            let bounds = AgentMarks.path(for: kind, in: box).boundingBox
            XCTAssertTrue(
                box.insetBy(dx: -0.5, dy: -0.5).contains(bounds),
                "\(kind.id) overflows its box: \(bounds)"
            )
        }
    }

    func testAZeroSizedBoxIsNotACrash() {
        for kind in AgentKind.known {
            XCTAssertTrue(AgentMarks.path(for: kind, in: .zero).isEmpty, kind.id)
        }
    }

    /// Claude's mark is the wide one; everything drawn is square. Getting this
    /// wrong stretches a mark instead of failing visibly.
    func testAspectsMatchTheArtwork() {
        XCTAssertEqual(AgentMarks.aspect(for: .claude), 1.6, accuracy: 0.001)
        for kind in [AgentKind.codex, .gemini, .opencode, .ollama] {
            XCTAssertEqual(AgentMarks.aspect(for: kind), 1, accuracy: 0.001, kind.id)
        }
    }
}

/// Two agents at once is a real state, not a corner case: a Claude Code session
/// and a Codex session on the same machine both signal independently.
final class ConcurrentAgentTests: XCTestCase {

    // Throwaway names, never `.claude` or `.codex`.
    //
    // These write to the *live* signal directory — that is the point, it is the
    // real channel the CLI and the watcher share — so a test that used a real
    // agent's name would delete that agent's signal on tearDown and blank the
    // notch of whoever happened to be running one. Which is exactly what
    // happened: a suite run mid-session wiped the Claude signal out from under
    // the app. Made-up names also exercise the open-agent path for free.
    private let first = AgentKind(name: "bondex-test-a")!
    private let second = AgentKind(name: "bondex-test-b")!

    override func tearDown() {
        try? AgentActivityService.markIdle(first)
        try? AgentActivityService.markIdle(second)
        super.tearDown()
    }

    func testEachAgentGetsItsOwnSignalFile() throws {
        try AgentActivityService.markBusy(first, status: "Editing")
        try AgentActivityService.markBusy(second, status: "Running tests")

        XCTAssertEqual(AgentActivityService.readSignal(for: first)?.status, "Editing")
        XCTAssertEqual(AgentActivityService.readSignal(for: second)?.status, "Running tests")

        // One going idle must not take the other down with it.
        try AgentActivityService.markIdle(first)
        XCTAssertNil(AgentActivityService.readSignal(for: first))
        XCTAssertEqual(AgentActivityService.readSignal(for: second)?.status, "Running tests")
    }

    /// The service discovers agents by listing the directory rather than by
    /// walking a fixed list, which is what lets an unknown agent appear at all.
    func testSignalledAgentsAreDiscoveredFromTheDirectory() throws {
        try AgentActivityService.markBusy(first, status: nil)
        try AgentActivityService.markBusy(second, status: nil)

        let found = Set(AgentActivityService.signalledAgents())
        XCTAssertTrue(found.contains(first), "an agent with no built-in support must still be found")
        XCTAssertTrue(found.contains(second))
    }
}
