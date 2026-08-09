import Foundation
import XCTest
@testable import BondexNotch

/// The Dev widget is a parser wrapped in a watcher, so the parser is where the
/// bugs live. Every fixture here is real `git status --porcelain=v2 --branch`
/// output, which is the only reason to trust that the field offsets are right.
final class DevStatusParsingTests: XCTestCase {

    func testBranchUpstreamAndDivergenceAreRead() {
        let output = """
        # branch.oid 9f2a1c0d4e5b6a7c8d9e0f1a2b3c4d5e6f708192
        # branch.head feat/dev-widget
        # branch.upstream origin/feat/dev-widget
        # branch.ab +2 -1
        """
        let snapshot = DevProjectService.parseStatus(output)

        XCTAssertEqual(snapshot.branch, "feat/dev-widget")
        XCTAssertEqual(snapshot.upstream, "origin/feat/dev-widget")
        XCTAssertEqual(snapshot.ahead, 2)
        XCTAssertEqual(snapshot.behind, 1)
        XCTAssertFalse(snapshot.isDetached)
        XCTAssertTrue(snapshot.isClean)
    }

    /// A branch with no upstream reports no `branch.ab` line at all, so ahead and
    /// behind must stay at zero rather than being left over or invented.
    func testABranchWithNoUpstreamHasNoDivergence() {
        let output = """
        # branch.oid 9f2a1c0d4e5b6a7c8d9e0f1a2b3c4d5e6f708192
        # branch.head local-only
        """
        let snapshot = DevProjectService.parseStatus(output)

        XCTAssertNil(snapshot.upstream)
        XCTAssertEqual(snapshot.ahead, 0)
        XCTAssertEqual(snapshot.behind, 0)
    }

    /// Detached HEAD reports the literal "(detached)" as the branch name, which
    /// is not something to show a user. The SHA is the useful answer.
    func testDetachedHeadShowsTheShortSHA() {
        let output = """
        # branch.oid 9f2a1c0d4e5b6a7c8d9e0f1a2b3c4d5e6f708192
        # branch.head (detached)
        """
        let snapshot = DevProjectService.parseStatus(output)

        XCTAssertTrue(snapshot.isDetached)
        XCTAssertEqual(snapshot.branch, "9f2a1c0")
    }

    func testOrdinaryEntriesAreSplitByWhereTheChangeIs() {
        // XY: index first, working tree second. ".M" is modified but unstaged,
        // "M." is staged, "MM" is both.
        let output = """
        # branch.head main
        1 .M N... 100644 100644 100644 aaa bbb Sources/App.swift
        1 M. N... 100644 100644 100644 ccc ddd Sources/Staged.swift
        1 MM N... 100644 100644 100644 eee fff Sources/Both.swift
        ? Sources/New.swift
        """
        let snapshot = DevProjectService.parseStatus(output)

        XCTAssertEqual(snapshot.modifiedCount, 1)
        // "Both" counts as staged: it is the more specific thing to say, and
        // listing one path twice would make the counts add up to more files than
        // the repository has.
        XCTAssertEqual(snapshot.stagedCount, 2)
        XCTAssertEqual(snapshot.untrackedCount, 1)
        XCTAssertFalse(snapshot.isClean)
    }

    func testPathsWithSpacesSurvive() {
        let output = """
        # branch.head main
        1 .M N... 100644 100644 100644 aaa bbb Design Notes/Read Me.md
        ? Untracked File.txt
        """
        let snapshot = DevProjectService.parseStatus(output)

        XCTAssertEqual(snapshot.changes.map(\.path).sorted(), [
            "Design Notes/Read Me.md",
            "Untracked File.txt"
        ])
    }

    /// A rename reports `<new>\t<old>`. Showing both, or showing the old one,
    /// points at a file that is no longer there.
    func testARenameReportsTheNewPathOnly() {
        let output = """
        # branch.head main
        2 R. N... 100644 100644 100644 aaa bbb R100 Sources/New.swift\tSources/Old.swift
        """
        let snapshot = DevProjectService.parseStatus(output)

        XCTAssertEqual(snapshot.changes.count, 1)
        XCTAssertEqual(snapshot.changes.first?.path, "Sources/New.swift")
    }

    func testConflictsAreReadAndSortedFirst() {
        let output = """
        # branch.head main
        ? z-untracked.txt
        1 .M N... 100644 100644 100644 aaa bbb a-modified.swift
        u UU N... 100644 100644 100644 100644 aaa bbb ccc Conflicted.swift
        """
        let snapshot = DevProjectService.parseStatus(output)

        XCTAssertEqual(snapshot.conflictCount, 1)
        XCTAssertEqual(
            snapshot.changes.first?.kind, .conflicted,
            "conflicts block everything else, so they belong at the top of a short list"
        )
        XCTAssertEqual(snapshot.changes.first?.path, "Conflicted.swift")
    }

    func testGarbageIsIgnoredRatherThanCrashing() {
        // Truncated lines are what a killed `git status` leaves behind.
        let output = """
        # branch.head main
        1 .M
        #
        u
        ?
        """
        let snapshot = DevProjectService.parseStatus(output)

        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertTrue(snapshot.isClean)
    }
}

final class DevCommitParsingTests: XCTestCase {

    func testTheLastCommitIsRead() {
        var snapshot = DevSnapshot()
        DevProjectService.applyLog("a1b2c3d\0Fix the thing\01769000000\n", to: &snapshot)

        XCTAssertEqual(snapshot.lastCommitHash, "a1b2c3d")
        XCTAssertEqual(snapshot.lastCommitSubject, "Fix the thing")
        XCTAssertEqual(snapshot.lastCommitDate, Date(timeIntervalSince1970: 1_769_000_000))
    }

    /// The fields are NUL-separated precisely so a subject can contain anything
    /// a person might type, tabs and pipes included.
    func testASubjectContainingSeparatorsSurvives() {
        var snapshot = DevSnapshot()
        DevProjectService.applyLog("a1b2c3d\0Fix a|b\tand c - d\01769000000", to: &snapshot)

        XCTAssertEqual(snapshot.lastCommitSubject, "Fix a|b\tand c - d")
    }

    func testAnEmptyRepositoryLeavesTheCommitUnset() {
        var snapshot = DevSnapshot()
        DevProjectService.applyLog("", to: &snapshot)

        XCTAssertNil(snapshot.lastCommitHash)
        XCTAssertNil(snapshot.lastCommitDate)
    }
}

final class DevOperationTests: XCTestCase {

    private func makeRepository(markers: [String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bondex-dev-\(UUID().uuidString)")
        let git = root.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        for marker in markers {
            try Data().write(to: git.appendingPathComponent(marker))
        }
        return root
    }

    func testAnIdleRepositoryReportsNoOperation() throws {
        let repository = try makeRepository(markers: [])
        defer { try? FileManager.default.removeItem(at: repository) }

        XCTAssertNil(DevProjectService.operationInProgress(at: repository))
    }

    func testAnUnfinishedMergeIsReported() throws {
        let repository = try makeRepository(markers: ["MERGE_HEAD"])
        defer { try? FileManager.default.removeItem(at: repository) }

        XCTAssertEqual(DevProjectService.operationInProgress(at: repository), "Merging")
    }

    func testAnUnfinishedRebaseIsReported() throws {
        let repository = try makeRepository(markers: ["rebase-merge"])
        defer { try? FileManager.default.removeItem(at: repository) }

        XCTAssertEqual(DevProjectService.operationInProgress(at: repository), "Rebasing")
    }
}

final class DevRepositoryRootTests: XCTestCase {

    private func makeRepository(gitIsAFile: Bool = false) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bondex-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources/Deep/Nested"),
            withIntermediateDirectories: true
        )
        let git = root.appendingPathComponent(".git")
        if gitIsAFile {
            // What a worktree or submodule checkout looks like.
            try "gitdir: /elsewhere/.git/worktrees/x".write(to: git, atomically: true, encoding: .utf8)
        } else {
            try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        }
        return root
    }

    /// Git works from anywhere inside a checkout, so picking `MyApp/Sources` has
    /// to find `MyApp` rather than report that there is no repository.
    func testASubdirectoryResolvesToTheRoot() throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let deep = root.appendingPathComponent("Sources/Deep/Nested")
        // Compared by path: a URL built as a directory carries a trailing slash
        // and one built from a path does not, so the two are unequal as URLs
        // while naming the same folder.
        XCTAssertEqual(
            DevProjectService.repositoryRoot(containing: deep)?.path,
            root.standardizedFileURL.path
        )
    }

    func testTheRootItselfResolvesToItself() throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(
            DevProjectService.repositoryRoot(containing: root)?.path,
            root.standardizedFileURL.path
        )
    }

    /// A worktree's `.git` is a file pointing elsewhere, not a directory.
    /// Checking `isDirectory` would reject every worktree checkout.
    func testAWorktreeWhoseGitIsAFileIsStillARepository() throws {
        let root = try makeRepository(gitIsAFile: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertNotNil(DevProjectService.repositoryRoot(containing: root))
    }

    func testAFolderOutsideAnyRepositoryResolvesToNothing() throws {
        let plain = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bondex-plain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plain) }

        // /tmp is not inside a checkout, so the walk has to terminate at / and
        // give up rather than run off the top of the filesystem.
        XCTAssertNil(DevProjectService.repositoryRoot(containing: plain))
    }
}

final class DevTabTests: XCTestCase {

    func testTheDevTabIsGatedAndScrolls() {
        XCTAssertEqual(NotchTab.dev.requiredFeature, .devTools)
        XCTAssertNotNil(
            NotchTab.dev.widgetHeight,
            "the change list scrolls, so the panel must not resize as files are edited"
        )
    }

    /// You ran the checkout, so being told about it over the menu bar is the app
    /// reporting your own keystroke back at you.
    func testBranchChangesReachTheFeedButNeverTheBanner() {
        XCTAssertFalse(NotchEvent.Kind.dev.deservesBanner)
    }
}
