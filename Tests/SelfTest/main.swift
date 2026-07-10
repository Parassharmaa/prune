import Foundation

enum SelfTestError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw SelfTestError.failed(message) }
}

func testPorcelainParser() throws {
    let fields = [
        "worktree /tmp/main repo",
        "HEAD 1111111111111111111111111111111111111111",
        "branch refs/heads/main",
        "",
        "worktree /tmp/feature repo",
        "HEAD 2222222222222222222222222222222222222222",
        "branch refs/heads/codex/feature",
        "locked active task",
        ""
    ]
    let result = WorktreePorcelainParser.parse(Data(fields.joined(separator: "\0").utf8))

    try expect(result.count == 2, "Parser should return two worktrees")
    try expect(result[0].path == "/tmp/main repo", "Parser should preserve spaces in paths")
    try expect(result[0].branch == "main", "Parser should remove refs/heads prefix")
    try expect(result[1].branch == "codex/feature", "Parser should preserve branch slashes")
    try expect(result[1].lockedReason == "active task", "Parser should capture lock reasons")
}

struct StubGitHubRunner: CommandRunning {
    func run(executable: String, arguments: [String], currentDirectory: URL?) throws -> CommandResult {
        if arguments.starts(with: ["repo", "view"]) {
            return CommandResult(stdout: Data("example/atlas\n".utf8), stderr: Data(), exitCode: 0)
        }
        let json = """
        [{"number":142,"state":"MERGED","isDraft":false,"mergedAt":"2026-07-10T00:00:00Z","url":"https://github.com/example/atlas/pull/142","title":"Merged feature","headRefOid":"abc123","updatedAt":"2026-07-10T00:00:00Z"}]
        """
        return CommandResult(stdout: Data(json.utf8), stderr: Data(), exitCode: 0)
    }
}

func testGitHubMergedHeadReadiness() throws {
    let snapshot = WorktreeSnapshot(
        repositoryName: "atlas",
        commonGitDirectory: URL(fileURLWithPath: "/tmp/atlas/.git"),
        path: URL(fileURLWithPath: "/tmp/atlas-feature"),
        head: "abc123",
        branch: "feature/auth",
        isMain: false,
        sizeBytes: 1_000,
        localState: .clean
    )
    let provider = GitHubPullRequestProvider(runner: StubGitHubRunner(), executable: "/stub/gh")
    let status = provider.status(for: snapshot)

    try expect(status.isMergedAtCurrentHead, "Matching merged PR head should be cleanup-ready")
    try expect(snapshot.replacingPullRequest(status).isReadyToClean, "Merged PR plus clean local state should be ready")
    try expect(
        !snapshot.replacingPullRequest(status).replacingSize(1_000).isMain,
        "Fixture should remain a linked worktree"
    )
}

func testRealRepositoryDiscovery() throws {
    let runner = SystemCommandRunner()
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("PruneTests-\(UUID().uuidString)", isDirectory: true)
    let main = root.appendingPathComponent("main", isDirectory: true)
    let linked = root.appendingPathComponent("linked tree", isDirectory: true)
    try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    _ = try runner.run(executable: "/usr/bin/git", arguments: ["init", "-b", "main"], currentDirectory: main)
    _ = try runner.run(executable: "/usr/bin/git", arguments: ["config", "user.email", "prune-tests@example.com"], currentDirectory: main)
    _ = try runner.run(executable: "/usr/bin/git", arguments: ["config", "user.name", "Prune Tests"], currentDirectory: main)
    try Data("seed\n".utf8).write(to: main.appendingPathComponent("README.md"))
    _ = try runner.run(executable: "/usr/bin/git", arguments: ["add", "README.md"], currentDirectory: main)
    _ = try runner.run(executable: "/usr/bin/git", arguments: ["commit", "-m", "seed"], currentDirectory: main)
    _ = try runner.run(
        executable: "/usr/bin/git",
        arguments: ["worktree", "add", "-b", "feature/test", linked.path],
        currentDirectory: main
    )

    let scanner = WorktreeScanner(runner: runner)
    var progressivelyDiscovered: [WorktreeSnapshot] = []
    let metadataSnapshots = try scanner.scanMetadata(roots: [root]) {
        progressivelyDiscovered.append($0)
    }
    try expect(progressivelyDiscovered.count == 2, "Metadata scan should publish each worktree immediately")
    try expect(metadataSnapshots.allSatisfy { $0.sizeBytes == nil }, "Metadata scan should not wait for disk sizes")

    let snapshots = try scanner.scan(roots: [root])
    try expect(snapshots.count == 2, "Scanner should find main and linked worktrees")
    try expect(
        snapshots.first(where: { $0.path == main.standardizedFileURL })?.localState == .mainCheckout,
        "Scanner should protect the main checkout"
    )
    try expect(
        snapshots.first(where: { $0.path == linked.standardizedFileURL })?.localState == .clean,
        "Scanner should classify a clean linked worktree"
    )

    guard let linkedSnapshot = snapshots.first(where: { $0.path == linked.standardizedFileURL }) else {
        throw SelfTestError.failed("Scanner did not return the linked worktree snapshot")
    }
    let cleanupExecutor = WorktreeCleanupExecutor(runner: runner)

    let untracked = linked.appendingPathComponent("untracked.txt")
    try Data("do not lose me\n".utf8).write(to: untracked)
    var dirtyRemovalWasBlocked = false
    do {
        _ = try cleanupExecutor.remove(linkedSnapshot)
    } catch WorktreeCleanupError.dirty(_) {
        dirtyRemovalWasBlocked = true
    }
    try expect(dirtyRemovalWasBlocked, "Cleanup should reject a newly dirty worktree")
    try expect(FileManager.default.fileExists(atPath: linked.path), "Rejected cleanup should preserve the worktree")

    let stashReadySnapshot = linkedSnapshot.replacingPullRequest(
        .merged(
            number: 99,
            url: URL(string: "https://github.com/example/repo/pull/99")!,
            title: "Merged fixture",
            headMatches: true
        )
    )
    let stashResult = try cleanupExecutor.remove(stashReadySnapshot, strategy: .stashThenRemove)
    try expect(stashResult.stashCommit != nil, "Stash-backed cleanup should report the created stash")
    let stashFiles = try runner.run(
        executable: "/usr/bin/git",
        arguments: ["stash", "show", "--include-untracked", "--name-only", stashResult.stashCommit!],
        currentDirectory: main
    )
    try expect(stashFiles.stdoutString.contains("untracked.txt"), "The recovery stash should contain untracked work")
    try expect(!FileManager.default.fileExists(atPath: linked.path), "Cleanup should remove the linked worktree")
    try expect(FileManager.default.fileExists(atPath: main.path), "Cleanup should preserve the main checkout")

    let cleanLinked = root.appendingPathComponent("clean linked tree", isDirectory: true)
    _ = try runner.run(
        executable: "/usr/bin/git",
        arguments: ["worktree", "add", "-b", "feature/clean", cleanLinked.path],
        currentDirectory: main
    )
    let cleanSnapshot = try scanner.scan(roots: [root]).first { $0.path == cleanLinked.standardizedFileURL }
    guard let cleanSnapshot else { throw SelfTestError.failed("Scanner did not return the clean fixture") }
    let cleanResult = try cleanupExecutor.remove(cleanSnapshot)
    try expect(cleanResult.stashCommit == nil, "Clean cleanup should not create a stash")
    try expect(!FileManager.default.fileExists(atPath: cleanLinked.path), "Clean cleanup should remove the linked worktree")
}

do {
    try testPorcelainParser()
    print("✓ porcelain parser")
    try testGitHubMergedHeadReadiness()
    print("✓ merged GitHub PR at current HEAD becomes ready")
    try testRealRepositoryDiscovery()
    print("✓ progressive metadata appears before sizes")
    print("✓ guarded cleanup rejects dirty state")
    print("✓ merged dirty cleanup stashes untracked work before removal")
    print("✓ clean cleanup removes without creating a stash")
    print("All Prune self-tests passed.")
} catch {
    fputs("Prune self-test failed: \(error)\n", stderr)
    exit(1)
}
