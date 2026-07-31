import Foundation

// MARK: - Model

/// One file Git has something to say about.
struct DevChange: Identifiable, Equatable {
    enum Kind: Equatable {
        case staged
        case modified
        case untracked
        case conflicted

        var glyph: String {
            switch self {
            case .staged: return "S"
            case .modified: return "M"
            case .untracked: return "U"
            case .conflicted: return "!"
            }
        }
    }

    /// Repository-relative path, which is what Git reports and what is short
    /// enough to read in a 560pt panel.
    let path: String
    let kind: Kind

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    /// Everything but the file name, for the dimmed prefix in the list.
    var directory: String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "" : parent + "/"
    }
}

/// The state of a working copy at one moment.
struct DevSnapshot: Equatable {
    var branch = ""
    /// True when HEAD is not on a branch, where `branch` holds the short SHA.
    var isDetached = false
    var upstream: String?
    var ahead = 0
    var behind = 0
    var changes: [DevChange] = []
    /// Set while a merge, rebase or cherry-pick is unfinished — the thing you
    /// most want to be reminded of, and the thing a branch name alone hides.
    var operation: String?
    var lastCommitHash: String?
    var lastCommitSubject: String?
    var lastCommitDate: Date?

    var stagedCount: Int { changes.count { $0.kind == .staged } }
    var modifiedCount: Int { changes.count { $0.kind == .modified } }
    var untrackedCount: Int { changes.count { $0.kind == .untracked } }
    var conflictCount: Int { changes.count { $0.kind == .conflicted } }

    var isClean: Bool { changes.isEmpty }
}

/// Why there is nothing to show.
///
/// Every case is something the user can act on, which is why this is a type
/// rather than a logged error: "Git not found" and "not a repository" have
/// completely different answers, and a widget that showed one blank state for
/// both would send the user looking in the wrong place.
enum DevProjectProblem: Error, Equatable {
    case noFolderChosen
    case notARepository(String)
    case gitUnavailable
    case unreadable(String)

    var title: String {
        switch self {
        case .noFolderChosen: return "No project chosen"
        case .notARepository: return "Not a Git repository"
        case .gitUnavailable: return "Git not found"
        case .unreadable: return "Could not read the project"
        }
    }

    var detail: String {
        switch self {
        case .noFolderChosen:
            return "Pick a folder in Settings › Widgets."
        case .notARepository(let path):
            return "\(path) has no .git directory."
        case .gitUnavailable:
            return "Install the Xcode Command Line Tools, or Git via Homebrew."
        case .unreadable(let reason):
            return reason
        }
    }

    var systemImage: String {
        switch self {
        case .noFolderChosen: return "folder.badge.questionmark"
        case .notARepository: return "questionmark.folder"
        case .gitUnavailable: return "wrench.and.screwdriver"
        case .unreadable: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Service

/// Reports the state of one Git working copy in the notch.
///
/// Watches the repository's `.git` directory rather than polling it. Git touches
/// `.git` for every operation that could change any of this — a commit, a
/// checkout, an index write, a fetch updating a remote ref — so a dispatch source
/// there fires exactly when there is something new to read and never in between.
/// The one thing it misses is an edit to a tracked file, which changes the file
/// and not the repository; that is what `refresh()` on the panel opening is for.
///
/// This is the only service that runs another program, so two rules apply that
/// the others do not need. Git is located explicitly rather than invoked as
/// `/usr/bin/git` — that path is a *shim* on a Mac without the Command Line
/// Tools, and running it pops the system "install developer tools" dialog, which
/// would be an unprompted modal from a menu bar app. And every invocation is
/// off the main actor with a timeout, because a repository on a stalled network
/// mount will otherwise hang whatever thread asked.
@MainActor
final class DevProjectService: ObservableObject {

    @Published private(set) var snapshot: DevSnapshot?
    @Published private(set) var problem: DevProjectProblem? = .noFolderChosen
    @Published private(set) var projectName: String?

    private let events: EventCenter
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var projectURL: URL?
    private var readTask: Task<Void, Never>?
    private var coalesceWork: DispatchWorkItem?
    /// Last branch reported, so a checkout can be announced once rather than on
    /// every read that happens to see the new name.
    private var lastAnnouncedBranch: String?

    init(events: EventCenter) {
        self.events = events
    }

    // MARK: Lifecycle

    func start(path: String?) {
        stop()

        guard let path, !path.isEmpty else {
            problem = .noFolderChosen
            snapshot = nil
            projectName = nil
            return
        }

        let chosen = URL(fileURLWithPath: path, isDirectory: true)
        guard let root = Self.repositoryRoot(containing: chosen) else {
            projectName = chosen.lastPathComponent
            problem = .notARepository(chosen.lastPathComponent)
            snapshot = nil
            return
        }

        projectURL = root
        projectName = root.lastPathComponent

        guard Self.gitExecutable != nil else {
            problem = .gitUnavailable
            snapshot = nil
            return
        }

        watch(root.appendingPathComponent(".git"))
        refresh()
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
        coalesceWork?.cancel()
        coalesceWork = nil
        readTask?.cancel()
        readTask = nil
        lastAnnouncedBranch = nil
    }

    /// Reads the working copy now. Called when the panel opens, because an edit
    /// to a tracked file changes the file and not `.git`, so nothing would have
    /// woken the watcher.
    func refresh() {
        guard let projectURL, let git = Self.gitExecutable else { return }
        guard readTask == nil else { return }

        readTask = Task { [weak self] in
            let result = await Self.read(git: git, at: projectURL)
            guard let self, !Task.isCancelled else { return }
            self.readTask = nil
            self.apply(result)
        }
    }

    private func apply(_ result: Result<DevSnapshot, DevProjectProblem>) {
        switch result {
        case .success(let fresh):
            problem = nil
            announceBranchChange(to: fresh)
            guard fresh != snapshot else { return }
            snapshot = fresh
        case .failure(let failure):
            problem = failure
            snapshot = nil
        }
    }

    /// Posts to the feed when the branch actually moves.
    ///
    /// Feed only, never a banner: you are the one who ran the checkout, so
    /// interrupting the screen to tell you about it would be reporting your own
    /// keystroke back at you. It earns its place in the feed as a timeline of
    /// what the working copy did while you were elsewhere.
    private func announceBranchChange(to fresh: DevSnapshot) {
        guard !fresh.branch.isEmpty else { return }
        defer { lastAnnouncedBranch = fresh.branch }
        guard let previous = lastAnnouncedBranch, previous != fresh.branch else { return }
        events.post(NotchEvent(
            kind: .dev,
            title: fresh.branch,
            subtitle: "Switched from \(previous)"
        ))
    }

    /// Walks up from a chosen folder to the working copy that contains it.
    ///
    /// Git commands work from anywhere inside a repository, so a picker that only
    /// accepted the exact root would reject `MyApp/Sources` — a folder the user
    /// has every reason to think of as "the project" — and say it was not a
    /// repository at all, which is both wrong and unhelpful.
    ///
    /// `.git` may be a *file* rather than a directory: that is what a worktree or
    /// a submodule looks like, and it points at the real directory elsewhere. Git
    /// resolves that itself, so the only question here is whether something is
    /// there at all.
    nonisolated static func repositoryRoot(
        containing url: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidate = url.standardizedFileURL
        // Bounded rather than looping until the path stops changing: a symlink
        // cycle or an unexpected root would otherwise spin here forever, and no
        // real checkout is anywhere near this deep.
        for _ in 0..<40 {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent(".git").path) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            guard parent != candidate else { return nil }
            candidate = parent
        }
        return nil
    }

    // MARK: Watching

    private func watch(_ gitDirectory: URL) {
        descriptor = open(gitDirectory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Log.dev.error("Could not watch \(gitDirectory.path, privacy: .public)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            onMainActor { self?.scheduleRead() }
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source
    }

    /// Git rewrites several files per operation — a commit touches the index,
    /// HEAD, a ref and the log — so the watcher fires a burst for what the user
    /// experienced as one action. Reading on each would run git repeatedly to
    /// produce the same answer, and would catch the repository halfway through.
    private func scheduleRead() {
        coalesceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.coalesceWork = nil
            self?.refresh()
        }
        coalesceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    // MARK: Git

    /// Where Git actually is, or nil if it is not installed.
    ///
    /// Deliberately not `/usr/bin/git`. On a Mac without the Command Line Tools
    /// that path exists but is a stub that pops the developer-tools installer,
    /// which is not something a menu bar widget gets to do uninvited. Checking
    /// for a real binary first means the widget says "Git not found" instead.
    nonisolated static let gitExecutable: URL? = {
        let candidates = [
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git"
        ]
        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }()

    private nonisolated static func read(
        git: URL,
        at url: URL
    ) async -> Result<DevSnapshot, DevProjectProblem> {
        await Task.detached(priority: .utility) { () -> Result<DevSnapshot, DevProjectProblem> in
            let status = run(
                git: git,
                arguments: ["-C", url.path, "status", "--porcelain=v2", "--branch"]
            )
            guard let status else {
                return .failure(.unreadable("git status did not finish in time."))
            }
            guard status.code == 0 else {
                // 128 is Git's "not a repository" among other refusals; the
                // message it printed is more useful than anything invented here.
                let message = status.error.trimmingCharacters(in: .whitespacesAndNewlines)
                if message.contains("not a git repository") {
                    return .failure(.notARepository(url.lastPathComponent))
                }
                return .failure(.unreadable(message.isEmpty ? "git exited \(status.code)." : message))
            }

            var snapshot = parseStatus(status.output)
            snapshot.operation = operationInProgress(at: url)

            if let log = run(
                git: git,
                arguments: ["-C", url.path, "log", "-1", "--format=%h%x00%s%x00%ct"]
            ), log.code == 0 {
                applyLog(log.output, to: &snapshot)
            }

            return .success(snapshot)
        }.value
    }

    /// Runs Git and waits, with a ceiling.
    ///
    /// A repository on an unreachable network mount blocks in the filesystem, not
    /// in Git, so there is nothing to interrupt from the inside. The process is
    /// terminated instead and the read reported as failed, which the widget shows
    /// rather than freezing on.
    private nonisolated static func run(
        git: URL,
        arguments: [String],
        timeout: TimeInterval = 4
    ) -> (output: String, error: String, code: Int32)? {
        let process = Process()
        process.executableURL = git
        process.arguments = arguments
        // Git reads the user's config and hooks otherwise; this is a read-only
        // status call and has no business running anything the repository ships.
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "GIT_OPTIONAL_LOCKS": "0",
            "GIT_TERMINAL_PROMPT": "0"
        ]

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return nil
        }

        // The deadline has to be armed *before* anything reads, because
        // `readDataToEndOfFile` blocks until the child closes its end — a
        // timeout checked after the read would only ever be evaluated once the
        // process it was meant to interrupt had already finished. Terminating
        // the child is what unblocks the read.
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        // stderr is drained on another queue rather than after stdout: a child
        // that fills one pipe blocks until someone empties it, so reading them
        // one after the other deadlocks whenever the second one fills first.
        // `git status` on a large repository is exactly that shape.
        let errorQueue = DispatchQueue(label: "com.bondex.notch.git-stderr")
        var errData = Data()
        errorQueue.async { errData = err.fileHandleForReading.readDataToEndOfFile() }

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        errorQueue.sync {}
        watchdog.cancel()

        // A process we killed has nothing useful to say, and its partial output
        // would parse as a repository with no changes in it.
        guard process.terminationReason != .uncaughtSignal else { return nil }

        return (
            String(decoding: outData, as: UTF8.self),
            String(decoding: errData, as: UTF8.self),
            process.terminationStatus
        )
    }

    // MARK: Parsing

    /// Parses `git status --porcelain=v2 --branch`.
    ///
    /// v2 rather than v1 because it reports the branch, its upstream and the
    /// ahead/behind counts in the same call — v1 would need three more
    /// invocations for what this gets in one. The format is documented as stable
    /// and machine-readable, which v1's is explicitly not.
    nonisolated static func parseStatus(_ output: String) -> DevSnapshot {
        var snapshot = DevSnapshot()
        // Git emits `branch.oid` *before* `branch.head`, so whether HEAD is
        // detached is not yet known when the SHA goes past. It is kept and
        // resolved after the loop rather than acted on in place.
        var headOID: String?

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let first = fields.first else { continue }

            switch first {
            case "#":
                guard fields.count >= 3 else { continue }
                switch fields[1] {
                case "branch.head":
                    let head = String(fields[2])
                    // Git says "(detached)" rather than naming anything.
                    snapshot.isDetached = head == "(detached)"
                    snapshot.branch = head
                case "branch.upstream":
                    snapshot.upstream = String(fields[2])
                case "branch.oid":
                    headOID = String(fields[2])
                case "branch.ab":
                    // "+2 -1"
                    guard fields.count >= 4 else { continue }
                    snapshot.ahead = Int(fields[2].dropFirst()) ?? 0
                    snapshot.behind = Int(fields[3].dropFirst()) ?? 0
                default:
                    continue
                }

            case "1", "2":
                // Ordinary and renamed entries. Field 1 is the two-character XY
                // status: X is the index, Y the working tree. A path can be both
                // staged and modified; it is listed once, as staged, because that
                // is the more specific thing to say about it.
                let isRenamed = first == "2"
                guard fields.count >= (isRenamed ? 10 : 9) else { continue }
                let xy = fields[1]
                let path = renamedOrPlainPath(fields: fields, isRenamed: isRenamed)
                guard !path.isEmpty else { continue }
                let index = xy.first ?? "."
                snapshot.changes.append(
                    DevChange(path: path, kind: index == "." ? .modified : .staged)
                )

            case "u":
                guard fields.count >= 11 else { continue }
                let path = fields[10...].joined(separator: " ")
                snapshot.changes.append(DevChange(path: path, kind: .conflicted))

            case "?":
                let path = fields[1...].joined(separator: " ")
                guard !path.isEmpty else { continue }
                snapshot.changes.append(DevChange(path: path, kind: .untracked))

            default:
                continue
            }
        }

        // "(detached)" is Git telling us there is no branch, not a name to show.
        if snapshot.isDetached, let headOID {
            snapshot.branch = String(headOID.prefix(7))
        }

        // Conflicts first — they are the only entries that block anything — then
        // staged, then the rest, so the top of a short list is the useful part.
        snapshot.changes.sort { lhs, rhs in
            if lhs.kind != rhs.kind { return rank(lhs.kind) < rank(rhs.kind) }
            return lhs.path < rhs.path
        }
        return snapshot
    }

    private nonisolated static func rank(_ kind: DevChange.Kind) -> Int {
        switch kind {
        case .conflicted: return 0
        case .staged: return 1
        case .modified: return 2
        case .untracked: return 3
        }
    }

    /// A renamed entry carries `<new path><tab><old path>`; only the new one is
    /// worth showing, since the old one no longer exists. Paths with spaces
    /// survive because the remainder of the line is rejoined rather than taken as
    /// a single field.
    ///
    /// The offsets are the count of fixed fields Git writes before the path:
    /// eight for an ordinary entry (`1 XY sub mH mI mW hH hI`), nine for a rename
    /// (`2 …` plus the similarity score).
    private nonisolated static func renamedOrPlainPath(fields: [Substring], isRenamed: Bool) -> String {
        let start = isRenamed ? 9 : 8
        guard fields.count > start else { return "" }
        let rest = fields[start...].joined(separator: " ")
        return String(rest.split(separator: "\t").first ?? "")
    }

    /// `%h<NUL>%s<NUL>%ct` — NUL-separated because a commit subject can contain
    /// anything else, tabs and pipes included.
    nonisolated static func applyLog(_ output: String, to snapshot: inout DevSnapshot) {
        let parts = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\0")
        guard parts.count >= 3 else { return }
        snapshot.lastCommitHash = parts[0]
        snapshot.lastCommitSubject = parts[1]
        if let seconds = TimeInterval(parts[2]) {
            snapshot.lastCommitDate = Date(timeIntervalSince1970: seconds)
        }
    }

    /// Whether the repository is mid-operation.
    ///
    /// Read from the marker files rather than by asking Git, which has no
    /// porcelain command that reports this — and the files are the same thing
    /// every shell prompt in the world checks for.
    nonisolated static func operationInProgress(
        at url: URL,
        fileManager: FileManager = .default
    ) -> String? {
        let git = url.appendingPathComponent(".git")
        let markers: [(String, String)] = [
            ("rebase-merge", "Rebasing"),
            ("rebase-apply", "Rebasing"),
            ("MERGE_HEAD", "Merging"),
            ("CHERRY_PICK_HEAD", "Cherry-picking"),
            ("REVERT_HEAD", "Reverting"),
            ("BISECT_LOG", "Bisecting")
        ]
        for (name, label) in markers
        where fileManager.fileExists(atPath: git.appendingPathComponent(name).path) {
            return label
        }
        return nil
    }
}
