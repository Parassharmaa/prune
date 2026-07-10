import Foundation

enum PruneSampleData {
    @MainActor
    static func makeStore() -> AppStore {
        let defaults = UserDefaults(suiteName: "dev.paras.prune.sample.\(UUID().uuidString)") ?? .standard
        return AppStore(
            cleanupExecutor: SampleCleanupExecutor(),
            pullRequestProvider: GitHubPullRequestProvider(
                runner: SampleGitHubRunner(),
                executable: "/sample/gh"
            ),
            defaults: defaults,
            initialWorktrees: worktrees,
            automaticallyStartsScanning: false,
            refreshesAfterCleanup: false
        )
    }

    static let worktrees: [WorktreeSnapshot] = {
        let common = URL(fileURLWithPath: "/Sample/Atlas/.git")
        return [
            WorktreeSnapshot(
                repositoryName: "atlas",
                commonGitDirectory: common,
                path: URL(fileURLWithPath: "/Sample/atlas-main"),
                head: "1111111111111111111111111111111111111111",
                branch: "main",
                isMain: true,
                sizeBytes: 12_800_000_000,
                localState: .mainCheckout
            ),
            WorktreeSnapshot(
                repositoryName: "atlas",
                commonGitDirectory: common,
                path: URL(fileURLWithPath: "/Sample/atlas-merged-auth"),
                head: "2222222222222222222222222222222222222222",
                branch: "feature/merged-auth",
                isMain: false,
                sizeBytes: 8_600_000_000,
                localState: .clean,
                pullRequest: .merged(
                    number: 142,
                    url: URL(string: "https://github.com/example/atlas/pull/142")!,
                    title: "Add merged authentication flow",
                    headMatches: true
                )
            ),
            WorktreeSnapshot(
                repositoryName: "atlas",
                commonGitDirectory: common,
                path: URL(fileURLWithPath: "/Sample/atlas-old-dashboard"),
                head: "3333333333333333333333333333333333333333",
                branch: "feature/old-dashboard",
                isMain: false,
                sizeBytes: 4_200_000_000,
                localState: .clean,
                pullRequest: .open(
                    number: 143,
                    isDraft: false,
                    url: URL(string: "https://github.com/example/atlas/pull/143")!,
                    title: "Old dashboard refresh"
                )
            ),
            WorktreeSnapshot(
                repositoryName: "atlas",
                commonGitDirectory: common,
                path: URL(fileURLWithPath: "/Sample/atlas-merged-local"),
                head: "5555555555555555555555555555555555555555",
                branch: "feature/merged-local",
                isMain: false,
                sizeBytes: 6_400_000_000,
                localState: .dirty(changeCount: 2),
                pullRequest: .merged(
                    number: 145,
                    url: URL(string: "https://github.com/example/atlas/pull/145")!,
                    title: "Merged work with local notes",
                    headMatches: true
                )
            ),
            WorktreeSnapshot(
                repositoryName: "atlas",
                commonGitDirectory: common,
                path: URL(fileURLWithPath: "/Sample/atlas-local-draft"),
                head: "4444444444444444444444444444444444444444",
                branch: "feature/local-draft",
                isMain: false,
                sizeBytes: 2_100_000_000,
                localState: .dirty(changeCount: 3),
                pullRequest: .open(
                    number: 144,
                    isDraft: true,
                    url: URL(string: "https://github.com/example/atlas/pull/144")!,
                    title: "Local draft"
                )
            )
        ]
    }()
}

private struct SampleGitHubRunner: CommandRunning {
    func run(executable: String, arguments: [String], currentDirectory: URL?) throws -> CommandResult {
        if arguments.starts(with: ["repo", "view"]) {
            return CommandResult(stdout: Data("example/atlas\n".utf8), stderr: Data(), exitCode: 0)
        }

        let branchIndex = arguments.firstIndex(of: "--head")
        let branch = branchIndex.flatMap { index in
            arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        } ?? ""
        let fixture: (number: Int, state: String, draft: Bool, mergedAt: String?, head: String)
        switch branch {
        case "feature/merged-auth": fixture = (142, "MERGED", false, "2026-07-10T00:00:00Z", "2222222222222222222222222222222222222222")
        case "feature/merged-local": fixture = (145, "MERGED", false, "2026-07-10T00:00:00Z", "5555555555555555555555555555555555555555")
        case "feature/old-dashboard": fixture = (143, "OPEN", false, nil, "3333333333333333333333333333333333333333")
        default: fixture = (144, "OPEN", true, nil, "4444444444444444444444444444444444444444")
        }
        let mergedAt = fixture.mergedAt.map { "\"\($0)\"" } ?? "null"
        let json = """
        [{"number":\(fixture.number),"state":"\(fixture.state)","isDraft":\(fixture.draft),"mergedAt":\(mergedAt),"url":"https://github.com/example/atlas/pull/\(fixture.number)","title":"Sample PR","headRefOid":"\(fixture.head)","updatedAt":"2026-07-10T00:00:00Z"}]
        """
        return CommandResult(stdout: Data(json.utf8), stderr: Data(), exitCode: 0)
    }
}

private struct SampleCleanupExecutor: WorktreeCleanupExecuting {
    func remove(_ snapshot: WorktreeSnapshot, strategy: CleanupStrategy) throws -> CleanupResult {
        Thread.sleep(forTimeInterval: 8.0)
        return CleanupResult(
            removedPath: snapshot.path,
            estimatedReclaimedBytes: snapshot.sizeBytes,
            stashCommit: strategy == .stashThenRemove ? "sample-stash-commit" : nil
        )
    }
}
