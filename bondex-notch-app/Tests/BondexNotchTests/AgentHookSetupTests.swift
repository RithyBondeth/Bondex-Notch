import XCTest
@testable import BondexNotch

/// Editing someone else's JSON without disturbing it.
final class OrderedJSONTests: XCTestCase {

    private func roundTrip(_ text: String) throws -> String {
        let data = Data(text.utf8)
        let value = try OrderedJSON.parse(data)
        return String(decoding: value.serialized(style: .detect(in: data)), as: UTF8.self)
    }

    /// Claude Code and Codex write `JSON.stringify(value, null, 2)`; such a
    /// file must come back exactly as it was.
    func testAFileWrittenLikeTheAgentsWriteItComesBackByteForByte() throws {
        let text = """
        {
          "theme": "dark",
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "\\"/Applications/Bondex Notch.app/Contents/MacOS/BondexNotch\\" --agent-hook claude",
                    "timeout": 2
                  }
                ]
              }
            ]
          },
          "numbers": [0, -1.50, 1e3, 2E-2, 12345678901234567890],
          "empty": {},
          "none": [],
          "flags": [true, false, null],
          "accents": "café ☕️ 😀",
          "tab": "a\\tb\\nc"
        }
        """
            // The inline array above is for readability; the agents put one
            // value per line.
            .replacingOccurrences(of: "[0, -1.50, 1e3, 2E-2, 12345678901234567890]", with: "[\n    0,\n    -1.50,\n    1e3,\n    2E-2,\n    12345678901234567890\n  ]")
            .replacingOccurrences(of: "[true, false, null]", with: "[\n    true,\n    false,\n    null\n  ]")

        XCTAssertEqual(try roundTrip(text), text)
        XCTAssertEqual(try roundTrip(text + "\n"), text + "\n")
    }

    func testKeyOrderAndDuplicateKeysSurvive() throws {
        let value = try OrderedJSON.parse(Data(#"{"z": 1, "a": 2, "z": 3}"#.utf8))
        guard case .object(let pairs) = value else { return XCTFail("not an object") }
        XCTAssertEqual(pairs.map(\.key), ["z", "a", "z"])
        // As JSON.parse reads it: the last one wins.
        XCTAssertEqual(value["z"], .number("3"))
    }

    func testTheIndentIsTheFilesOwn() throws {
        let fourSpaces = "{\n    \"a\": {\n        \"b\": 1\n    }\n}"
        XCTAssertEqual(try roundTrip(fourSpaces), fourSpaces)
        let tabs = "{\n\t\"a\": [\n\t\t1\n\t]\n}\n"
        XCTAssertEqual(try roundTrip(tabs), tabs)
    }

    /// A comment is not JSON. The file is left alone rather than "fixed".
    func testAnythingThatIsNotPlainJSONIsRefused() {
        for text in [
            "{\n  // a comment\n  \"a\": 1\n}",
            #"{"a": 1,}"#,
            #"{"a": 1} trailing"#,
            #"{"a": 01}"#,
            #"{"a": "unterminated}"#,
            #"{"a": "\ud83d"}"#
        ] {
            XCTAssertThrowsError(try OrderedJSON.parse(Data(text.utf8)), text)
        }
    }

    func testEscapesReadToTheirCharacters() throws {
        let value = try OrderedJSON.parse(Data(#"{"a": "caf\u00e9 \ud83d\ude00 \/ \"q\""}"#.utf8))
        XCTAssertEqual(value["a"], .string("café 😀 / \"q\""))
        // Written the way JSON.stringify writes it: only what must be escaped.
        XCTAssertEqual(
            String(decoding: value.serialized(style: .init(indent: "  ", trailingNewline: false)), as: UTF8.self),
            "{\n  \"a\": \"café 😀 / \\\"q\\\"\"\n}"
        )
    }
}

/// One-click hook setup for Claude Code and Codex.
final class AgentHookSetupTests: XCTestCase {

    private var home: URL!
    private let binary = "/Applications/Bondex Notch.app/Contents/MacOS/BondexNotch"
    private let oldBinary = "/Users/someone/Downloads/Bondex Notch.app/Contents/MacOS/BondexNotch"

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("Bondex-Hooks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func setup(_ kind: AgentKind, createDirectory: Bool = true) throws -> AgentHookSetup {
        let target = try XCTUnwrap(AgentHookSetup.Target.standard(for: kind, home: home, environment: [:]))
        if createDirectory {
            try FileManager.default.createDirectory(at: target.agentDirectory, withIntermediateDirectories: true)
        }
        return AgentHookSetup(target: target, binaryPath: binary)
    }

    private func hook(_ command: String) -> String {
        """
        {
                "hooks": [
                  {
                    "type": "command",
                    "command": \(Self.quoted(command)),
                    "timeout": 2
                  }
                ]
              }
        """
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func command(_ path: String, _ arguments: String) -> String {
        "\"\(path)\" \(arguments)"
    }

    /// Shaped like a real setup from before "Needs you": five events, one of
    /// them an explicit `--agent-idle`, beside settings and a hook of the
    /// person's own.
    private func olderClaudeSettings(path: String) -> String {
        """
        {
          "hooks": {
            "UserPromptSubmit": [
              \(hook(command(path, "--agent-hook claude")))
            ],
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  {
                    "type": "command",
                    "command": "~/bin/audit-bash"
                  }
                ]
              },
              \(hook(command(path, "--agent-hook claude")))
            ],
            "Stop": [
              \(hook(command(path, "--agent-hook claude")))
            ],
            "StopFailure": [
              \(hook(command(path, "--agent-idle claude")))
            ],
            "SessionEnd": [
              \(hook(command(path, "--agent-hook claude")))
            ]
          },
          "theme": "dark",
          "inputNeededNotifEnabled": true
        }
        """
    }

    private func write(_ text: String, to setup: AgentHookSetup) throws {
        try Data(text.utf8).write(to: setup.target.file)
    }

    private func read(_ setup: AgentHookSetup) throws -> OrderedJSON {
        try OrderedJSON.parse(Data(contentsOf: setup.target.file))
    }

    private func bondexCommands(_ root: OrderedJSON, event: String) -> [String] {
        (root["hooks"]?[event]?.arrayValue ?? [])
            .flatMap { $0["hooks"]?.arrayValue ?? [] }
            .compactMap { $0["command"]?.stringValue }
            .filter { AgentHookSetup.BondexCommand($0) != nil }
    }

    // MARK: State

    func testAnAgentThatIsNotInstalledIsSaidSo() throws {
        let claude = try setup(.claude, createDirectory: false)
        XCTAssertEqual(claude.state(), .agentMissing)
        XCTAssertThrowsError(try claude.install())
    }

    func testAnOlderSetupIsMissingTheEventsThatMeanNeedsYou() throws {
        let claude = try setup(.claude)
        try write(olderClaudeSettings(path: binary), to: claude)
        XCTAssertEqual(claude.state(), .incomplete(missing: ["PostToolUse", "PermissionRequest", "Notification"]))
    }

    func testASetupForAMovedAppIsCaught() throws {
        let claude = try setup(.claude)
        try write(olderClaudeSettings(path: oldBinary), to: claude)
        try claude.install()
        XCTAssertEqual(claude.state(), .ready)

        let other = AgentHookSetup(target: claude.target, binaryPath: "/Applications/Other/BondexNotch")
        XCTAssertEqual(other.state(), .otherCopy(path: binary))
    }

    // MARK: Installing

    func testAFreshInstallWiresEveryEvent() throws {
        let claude = try setup(.claude)
        XCTAssertEqual(claude.state(), .notSetUp)

        let change = try claude.install()
        XCTAssertEqual(change, .updated(added: claude.target.events, repointed: 0, removed: 0, backup: nil))
        XCTAssertEqual(claude.state(), .ready)

        let root = try read(claude)
        for event in claude.target.events {
            XCTAssertEqual(bondexCommands(root, event: event), [claude.command], event)
        }
        XCTAssertEqual(claude.command, "\"\(binary)\" --agent-hook claude")
    }

    /// The point of editing rather than writing: everything that was there
    /// stays, in its place.
    func testUpdatingAddsOnlyWhatIsMissing() throws {
        let claude = try setup(.claude)
        let original = olderClaudeSettings(path: binary)
        try write(original, to: claude)

        let change = try claude.install()
        guard case .updated(let added, let repointed, _, let backup) = change else { return XCTFail("\(change)") }
        XCTAssertEqual(added, ["PostToolUse", "PermissionRequest", "Notification"])
        XCTAssertEqual(repointed, 0)

        let before = try OrderedJSON.parse(Data(original.utf8))
        let after = try read(claude)
        guard case .object(let topBefore) = before, case .object(let topAfter) = after,
              case .object(let eventsBefore)? = before["hooks"], case .object(let eventsAfter)? = after["hooks"]
        else { return XCTFail("not objects") }

        XCTAssertEqual(topAfter.map(\.key), topBefore.map(\.key))
        XCTAssertEqual(after["theme"], before["theme"])
        // Existing events untouched and first; new ones appended after them.
        XCTAssertEqual(Array(eventsAfter.prefix(eventsBefore.count)).map(\.key), eventsBefore.map(\.key))
        for (index, event) in eventsBefore.enumerated() {
            XCTAssertEqual(eventsAfter[index].value, event.value, event.key)
        }
        XCTAssertEqual(eventsAfter.dropFirst(eventsBefore.count).map(\.key), added)

        // The original is kept, byte for byte.
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backup)), Data(original.utf8))
        XCTAssertEqual(backup?.lastPathComponent, "settings.json.bondex-backup")

        XCTAssertEqual(try claude.install(), .unchanged)
    }

    /// Moving the app breaks every hook at once. Repointing changes the path
    /// and nothing else — an explicit `--agent-idle` stays explicit.
    func testAMovedAppIsRepointedInPlace() throws {
        let claude = try setup(.claude)
        try write(olderClaudeSettings(path: oldBinary), to: claude)

        let change = try claude.install()
        guard case .updated(_, let repointed, _, _) = change else { return XCTFail("\(change)") }
        XCTAssertEqual(repointed, 5)

        let root = try read(claude)
        XCTAssertEqual(bondexCommands(root, event: "StopFailure"), [command(binary, "--agent-idle claude")])
        XCTAssertEqual(
            root["hooks"]?["PreToolUse"]?.arrayValue?.first?["hooks"]?.arrayValue?.first?["command"],
            .string("~/bin/audit-bash")
        )
    }

    /// Codex keys its trust on each hook's position, so a hook that is already
    /// trusted must stay exactly where it is.
    func testCodexKeepsItsTrustedHooksWhereTheyAre() throws {
        let codex = try setup(.codex)
        let raw = """
        {
          "description": "Report active agent work to Bondex Notch.",
          "hooks": {
            "UserPromptSubmit": [
              \(hook(command(binary, "--agent-hook codex")))
            ],
            "PreToolUse": [
              \(hook(command(binary, "--agent-hook codex")))
            ],
            "Stop": [
              \(hook(command(binary, "--agent-hook codex")))
            ],
            "SessionEnd": [
              \(hook(command(binary, "--agent-hook codex")))
            ]
          }
        }
        """
        // Laid out the way Codex writes it, so the text can be compared.
        let original = String(decoding: try OrderedJSON.parse(Data(raw.utf8)).serialized(), as: UTF8.self)
        try write(original, to: codex)
        XCTAssertEqual(codex.state(), .incomplete(missing: ["PostToolUse", "PermissionRequest"]))

        try codex.install()
        let text = try String(contentsOf: codex.target.file, encoding: .utf8)
        // Every line up to the end of the last original hook is unchanged:
        // the new events only follow it.
        let unchangedPrefix = original.components(separatedBy: "\n").dropLast(4).joined(separator: "\n")
        XCTAssertTrue(text.hasPrefix(unchangedPrefix + "\n    ],\n    \"PostToolUse\""), text)
        XCTAssertEqual(codex.state(), .ready)
        XCTAssertTrue(codex.target.asksToTrustChanges)
    }

    // MARK: Removing

    func testRemovingTakesOutOnlyBondex() throws {
        let claude = try setup(.claude)
        try write(olderClaudeSettings(path: binary), to: claude)
        try claude.install()

        let change = try claude.remove()
        guard case .updated(_, _, let removed, _) = change else { return XCTFail("\(change)") }
        XCTAssertEqual(removed, claude.target.events.count)

        let root = try read(claude)
        guard case .object(let events)? = root["hooks"] else { return XCTFail("hooks gone") }
        // Only the person's own hook is left, with its matcher.
        XCTAssertEqual(events.map(\.key), ["PreToolUse"])
        XCTAssertEqual(root["hooks"]?["PreToolUse"]?.arrayValue?.count, 1)
        XCTAssertEqual(root["hooks"]?["PreToolUse"]?.arrayValue?.first?["matcher"], .string("Bash"))
        XCTAssertEqual(root["theme"], .string("dark"))
        XCTAssertEqual(claude.state(), .notSetUp)
    }

    func testRemovingTheOnlyHooksTakesTheEmptyBlockToo() throws {
        let claude = try setup(.claude)
        try write("{\n  \"theme\": \"dark\"\n}\n", to: claude)
        try claude.install()
        try claude.remove()
        XCTAssertEqual(try String(contentsOf: claude.target.file, encoding: .utf8), "{\n  \"theme\": \"dark\"\n}\n")
    }

    // MARK: Files that must not be touched

    func testAFileThatIsNotPlainJSONIsLeftAlone() throws {
        let claude = try setup(.claude)
        let original = "{\n  // mine\n  \"theme\": \"dark\"\n}\n"
        try write(original, to: claude)

        guard case .unreadable = claude.state() else { return XCTFail("\(claude.state())") }
        XCTAssertThrowsError(try claude.install())
        XCTAssertEqual(try String(contentsOf: claude.target.file, encoding: .utf8), original)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: claude.target.file.appendingPathExtension("bondex-backup").path
        ))
    }

    func testAHooksBlockOfTheWrongShapeIsLeftAlone() throws {
        let claude = try setup(.claude)
        try write(#"{"hooks": {"Stop": "not a list"}}"#, to: claude)
        XCTAssertThrowsError(try claude.install())
        XCTAssertEqual(try String(contentsOf: claude.target.file, encoding: .utf8), #"{"hooks": {"Stop": "not a list"}}"#)
    }

    /// Settings kept in a dotfiles repository are linked into place.
    func testALinkedSettingsFileIsEditedThroughTheLink() throws {
        let claude = try setup(.claude)
        let dotfiles = home.appendingPathComponent("dotfiles", isDirectory: true)
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        let real = dotfiles.appendingPathComponent("claude-settings.json")
        try Data("{}\n".utf8).write(to: real)
        try FileManager.default.createSymbolicLink(at: claude.target.file, withDestinationURL: real)

        try claude.install()

        let attributes = try FileManager.default.attributesOfItem(atPath: claude.target.file.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertEqual(bondexCommands(try OrderedJSON.parse(Data(contentsOf: real)), event: "Stop"), [claude.command])
    }

    func testALockedDownFileStaysLockedDown() throws {
        let claude = try setup(.claude)
        try write("{}\n", to: claude)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: claude.target.file.path)

        try claude.install()

        let attributes = try FileManager.default.attributesOfItem(atPath: claude.target.file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    // MARK: Recognising Bondex

    func testBondexIsRecognisedHoweverItsPathIsQuoted() {
        for text in [
            #""/Applications/Bondex Notch.app/Contents/MacOS/BondexNotch" --agent-hook claude"#,
            #"'/Applications/Bondex Notch.app/Contents/MacOS/BondexNotch' --agent-hook claude"#,
            #"/Applications/Bondex\ Notch.app/Contents/MacOS/BondexNotch --agent-busy claude Working"#
        ] {
            let command = AgentHookSetup.BondexCommand(text)
            XCTAssertEqual(command?.binary, binary, text)
            XCTAssertEqual(command?.runs(.claude), true, text)
        }
        XCTAssertNil(AgentHookSetup.BondexCommand("echo --agent-hook claude"))
        XCTAssertNil(AgentHookSetup.BondexCommand("~/bin/audit-bash"))
        XCTAssertEqual(AgentHookSetup.BondexCommand(command(binary, "--agent-hook codex"))?.runs(.claude), false)
    }

    func testClaudesConfigFolderSettingIsHonoured() throws {
        let custom = home.appendingPathComponent("claude-work", isDirectory: true)
        let target = AgentHookSetup.Target.standard(
            for: .claude,
            home: home,
            environment: ["CLAUDE_CONFIG_DIR": custom.path]
        )
        XCTAssertEqual(target?.file, custom.appendingPathComponent("settings.json"))
        XCTAssertNil(AgentHookSetup.Target.standard(for: .gemini, home: home, environment: [:]))
    }
}
