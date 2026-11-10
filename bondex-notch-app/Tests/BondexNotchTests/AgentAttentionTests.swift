import AppKit
import XCTest
@testable import BondexNotch

/// "Needs you": an agent stopped for a permission prompt, a question or a plan
/// to approve.
final class AgentAttentionHookTests: XCTestCase {

    private func action(_ object: [String: Any]) throws -> AgentHookAction {
        AgentHookInput.action(from: try JSONSerialization.data(withJSONObject: object))
    }

    func testAPermissionRequestNeedsYou() throws {
        XCTAssertEqual(try action([
            "hook_event_name": "PermissionRequest",
            "tool_name": "Bash",
            "tool_input": ["command": "swift test"]
        ]), .attention(message: "Approve: Running swift test"))
    }

    /// A turn that dies on an API error sends StopFailure instead of Stop.
    func testATurnThatFailedIsIdle() throws {
        XCTAssertEqual(try action(["hook_event_name": "StopFailure"]), .idle)
    }

    // MARK: Gemini CLI

    /// The base fields Gemini CLI 0.55 sent, as captured from a real run.
    private func gemini(_ event: String, _ fields: [String: Any] = [:]) throws -> AgentHookAction {
        var object: [String: Any] = [
            "session_id": "3f1c", "cwd": "/tmp/work", "transcript_path": "/tmp/t.json",
            "timestamp": "2026-10-07T01:35:31.789Z", "hook_event_name": event
        ]
        object.merge(fields) { _, new in new }
        return try action(object)
    }

    /// Gemini names the same moments differently.
    func testAGeminiTurnReadsLikeAnyOther() throws {
        XCTAssertEqual(try gemini("BeforeAgent", ["prompt": "fix the build"]), .busy(status: "Thinking"))
        XCTAssertEqual(try gemini("BeforeTool", [
            "tool_name": "run_shell_command",
            "tool_input": ["command": "npm test", "description": "Running the test suite"]
        ]), .busy(status: "Running the test suite"))
        XCTAssertEqual(try gemini("BeforeTool", [
            "tool_name": "run_shell_command", "tool_input": ["command": "npm test"]
        ]), .busy(status: "Running npm test"))
        XCTAssertEqual(try gemini("AfterTool", [
            "tool_name": "replace", "tool_input": ["file_path": "/tmp/work/main.ts"]
        ]), .busy(status: "Editing main.ts"))
        XCTAssertEqual(try gemini("BeforeTool", ["tool_name": "grep_search", "tool_input": [:]]),
                       .busy(status: "Searching the code"))
        XCTAssertEqual(try gemini("AfterAgent", ["prompt_response": "Done."]), .idle)
        XCTAssertEqual(try gemini("SessionEnd", ["reason": "exit"]), .idle)
        XCTAssertEqual(try gemini("SessionStart", ["source": "startup"]), .ignore)
    }

    /// Gemini's approval prompt arrives as a Notification. Its own message
    /// ("Tool Shell requires execution") is replaced by what the tool will do.
    func testAGeminiApprovalNeedsYou() throws {
        XCTAssertEqual(try gemini("Notification", [
            "notification_type": "ToolPermission",
            "message": "Tool Shell requires execution",
            "details": ["type": "exec", "title": "Shell", "command": "rm -rf build", "rootCommand": "rm"]
        ]), .attention(message: "Approve: Running rm -rf build"))
        XCTAssertEqual(try gemini("Notification", [
            "notification_type": "ToolPermission",
            "message": "Tool Edit requires editing",
            "details": ["type": "edit", "title": "Edit", "fileName": "main.ts"]
        ]), .attention(message: "Approve: Editing main.ts"))
        XCTAssertEqual(try gemini("Notification", [
            "notification_type": "ToolPermission",
            "message": "Tool requires confirmation"
        ]), .attention(message: "Needs your approval"))
    }

    func testAGeminiQuestionOrPlanNeedsYou() throws {
        XCTAssertEqual(try gemini("BeforeTool", ["tool_name": "ask_user", "tool_input": [:]]),
                       .attention(message: "Has a question for you"))
        XCTAssertEqual(try gemini("BeforeTool", ["tool_name": "exit_plan_mode", "tool_input": [:]]),
                       .attention(message: "Plan ready for review"))
    }

    func testAPermissionPromptNotificationNeedsYou() throws {
        XCTAssertEqual(try action([
            "hook_event_name": "Notification",
            "notification_type": "permission_prompt",
            "message": "Claude needs your permission to use Bash"
        ]), .attention(message: "Claude needs your permission to use Bash"))
    }

    /// The idle reminder fires after a turn has already ended; the agent is not
    /// blocked on anything, so it must not light the notch.
    func testTheIdleReminderIsNotAWait() throws {
        XCTAssertEqual(try action([
            "hook_event_name": "Notification",
            "notification_type": "idle_prompt",
            "message": "Claude is waiting for your input"
        ]), .ignore)
    }

    /// Builds that do not label their notifications.
    func testAnUnlabelledNotificationIsReadFromItsMessage() throws {
        XCTAssertEqual(try action([
            "hook_event_name": "Notification",
            "message": "Claude needs your permission to use Edit"
        ]), .attention(message: "Claude needs your permission to use Edit"))
        XCTAssertEqual(try action([
            "hook_event_name": "Notification",
            "message": "Claude is waiting for your input"
        ]), .ignore)
    }

    func testAQuestionOrAPlanNeedsYou() throws {
        XCTAssertEqual(
            try action(["hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion", "tool_input": [:]]),
            .attention(message: "Has a question for you")
        )
        XCTAssertEqual(
            try action(["hook_event_name": "PreToolUse", "tool_name": "ExitPlanMode", "tool_input": [:]]),
            .attention(message: "Plan ready for review")
        )
    }

    /// Once the question has been answered the tool finishes, and the agent is
    /// working again.
    func testAnAnsweredQuestionIsWorkAgain() throws {
        guard case .busy = try action([
            "hook_event_name": "PostToolUse", "tool_name": "AskUserQuestion", "tool_input": [:]
        ]) else { return XCTFail("an answered question should read as work") }
    }

    func testClaudeFileToolsNameTheFile() throws {
        XCTAssertEqual(try action([
            "hook_event_name": "PreToolUse",
            "tool_name": "Edit",
            "tool_input": ["file_path": "/repo/Views/PeekView.swift"]
        ]), .busy(status: "Editing PeekView.swift"))
        XCTAssertEqual(try action([
            "hook_event_name": "PreToolUse",
            "tool_name": "Read",
            "tool_input": ["file_path": "/repo/README.md"]
        ]), .busy(status: "Reading README.md"))
    }

    func testTheAttentionFlagParses() {
        guard case .command(.attention(let kind, let message)) = AgentSignalCommand.parse(
            ["bondex", "--agent-attention", "gemini", "Approve", "the", "edit"]
        ) else { return XCTFail("--agent-attention should parse") }
        XCTAssertEqual(kind, .gemini)
        XCTAssertEqual(message, "Approve the edit")
    }
}

final class AgentAttentionSignalTests: XCTestCase {

    /// A made-up name: this writes to the live signal directory.
    private let agent = AgentKind(name: "bondex-test-attention")!

    override func tearDown() {
        try? AgentActivityService.markIdle(agent)
        super.tearDown()
    }

    func testAWaitRoundTripsAndTheNextBusyClearsIt() throws {
        try AgentActivityService.markNeedsAttention(agent, message: "Approve: Running swift test")
        let waiting = try XCTUnwrap(AgentActivityService.readSignal(for: agent))
        XCTAssertTrue(waiting.needsAttention)
        XCTAssertEqual(waiting.status, "Approve: Running swift test")

        try AgentActivityService.markBusy(agent, status: "Running swift test")
        let working = try XCTUnwrap(AgentActivityService.readSignal(for: agent))
        XCTAssertFalse(working.needsAttention)
    }

    /// A busy status can never pose as a wait, whatever it contains.
    func testABusyStatusCannotMarkAWait() throws {
        try AgentActivityService.markBusy(agent, status: "Editing\nattention")
        XCTAssertFalse(try XCTUnwrap(AgentActivityService.readSignal(for: agent)).needsAttention)
    }

    /// Waiting is exactly when no heartbeat arrives, so the ordinary 90-second
    /// backstop would drop the agent the moment it most needs to be seen.
    func testAWaitOutlivesTheWorkingBackstop() {
        let now = Date()
        let tenMinutesAgo = now.addingTimeInterval(-600)
        XCTAssertTrue(AgentActivityService.isFresh((tenMinutesAgo, nil, true), at: now))
        XCTAssertFalse(AgentActivityService.isFresh((tenMinutesAgo, nil, false), at: now))
        XCTAssertFalse(AgentActivityService.isFresh(
            (now.addingTimeInterval(-AgentActivityService.attentionStaleAfter - 1), nil, true),
            at: now
        ))
    }
}

@MainActor
final class AgentAttentionPeekTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "com.bondex.notch.tests.attention.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func model() throws -> NotchViewModel {
        NotchViewModel(
            settings: SettingsStore(defaults: defaults),
            events: EventCenter(),
            screen: try XCTUnwrap(NSScreen.main)
        )
    }

    /// A running focus timer outranks an agent that is merely working — but
    /// not one that is stuck waiting for you.
    func testAWaitingAgentOutranksTheFocusTimer() throws {
        let notch = try model()
        notch.hasFocusTimer = true
        notch.hasLiveActivity = true
        notch.workingAgentCount = 1
        XCTAssertEqual(notch.peekContent, .focus)

        notch.attentionAgentCount = 1
        XCTAssertEqual(notch.peekContent, .agent(agents: 1))
    }

    func testAWaitingAgentStillYieldsToHardwareFeedback() throws {
        let notch = try model()
        notch.workingAgentCount = 1
        notch.attentionAgentCount = 1
        notch.show(systemHUD: SystemHUDPresentation(kind: .volume, level: 0.5))
        XCTAssertEqual(notch.peekContent, .systemHUD)
    }
}
