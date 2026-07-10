import Foundation

protocol WorktreeCleanupExecuting: Sendable {
    func remove(_ snapshot: WorktreeSnapshot, strategy: CleanupStrategy) throws -> CleanupResult
}

enum CleanupStrategy: Sendable, Equatable {
    case removeClean
    case stashThenRemove
}

struct CleanupResult: Sendable {
    let removedPath: URL
    let estimatedReclaimedBytes: Int64?
    let stashCommit: String?
}

enum WorktreeCleanupError: LocalizedError, Sendable {
    case mainCheckout
    case missing
    case registrationChanged
    case locked(String?)
    case prunable(String)
    case dirty(Int)
    case stashRequiresMergedPullRequest
    case stashIncomplete
    case removalFailedAfterStash(commit: String, reason: String)
    case containsSubmodules
    case mainCheckoutUnavailable
    case removalIncomplete

    var errorDescription: String? {
        switch self {
        case .mainCheckout:
            "The main checkout is permanently protected."
        case .missing:
            "The worktree folder no longer exists. Refresh Prune and try again."
        case .registrationChanged:
            "Git's worktree registration changed since the last scan. Refresh and review it again."
        case .locked(let reason):
            reason.map { "This worktree is locked: \($0)" } ?? "This worktree is locked."
        case .prunable(let reason):
            "Git reports broken worktree metadata: \(reason)"
        case .dirty(let count):
            "The worktree now has \(count) local change\(count == 1 ? "" : "s"). Nothing was removed."
        case .stashRequiresMergedPullRequest:
            "Stash & Clean Up is available only when the pull request is merged at the current commit."
        case .stashIncomplete:
            "Git did not create a new stash or the worktree remained dirty. Nothing was removed."
        case .removalFailedAfterStash(let commit, let reason):
            "The changes are safe in stash \(commit), but worktree removal failed: \(reason)"
        case .containsSubmodules:
            "Worktrees with registered submodules require manual review. Nothing was removed."
        case .mainCheckoutUnavailable:
            "Prune could not find a usable main checkout for the removal command."
        case .removalIncomplete:
            "Git returned successfully, but the worktree folder still exists."
        }
    }
}

struct WorktreeCleanupExecutor: WorktreeCleanupExecuting, Sendable {
    private let runner: any CommandRunning

    init(runner: any CommandRunning = SystemCommandRunner()) {
        self.runner = runner
    }

    func remove(
        _ snapshot: WorktreeSnapshot,
        strategy: CleanupStrategy = .removeClean
    ) throws -> CleanupResult {
        guard !snapshot.isMain else { throw WorktreeCleanupError.mainCheckout }
        guard FileManager.default.fileExists(atPath: snapshot.path.path) else {
            throw WorktreeCleanupError.missing
        }

        let commonDirectoryResult = try runner.run(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"],
            currentDirectory: snapshot.path
        )
        let currentCommonDirectory = URL(
            fileURLWithPath: commonDirectoryResult.stdoutString
                .trimmingCharacters(in: .whitespacesAndNewlines)
        ).standardizedFileURL
        guard currentCommonDirectory == snapshot.commonGitDirectory.standardizedFileURL else {
            throw WorktreeCleanupError.registrationChanged
        }

        let listResult = try runner.run(
            executable: "/usr/bin/git",
            arguments: ["worktree", "list", "--porcelain", "-z"],
            currentDirectory: snapshot.path
        )
        let worktrees = WorktreePorcelainParser.parse(listResult.stdout)
        guard let registeredIndex = worktrees.firstIndex(where: {
            URL(fileURLWithPath: $0.path).standardizedFileURL == snapshot.path.standardizedFileURL
        }) else {
            throw WorktreeCleanupError.registrationChanged
        }
        guard registeredIndex != 0 else { throw WorktreeCleanupError.mainCheckout }

        let registered = worktrees[registeredIndex]
        if let reason = registered.lockedReason {
            throw WorktreeCleanupError.locked(reason.isEmpty ? nil : reason)
        }
        if let reason = registered.prunableReason {
            throw WorktreeCleanupError.prunable(reason)
        }

        let submoduleResult = try runner.run(
            executable: "/usr/bin/git",
            arguments: ["submodule", "status", "--recursive"],
            currentDirectory: snapshot.path
        )
        guard submoduleResult.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorktreeCleanupError.containsSubmodules
        }

        let statusResult = try runner.run(
            executable: "/usr/bin/git",
            arguments: ["status", "--porcelain=v1", "--untracked-files=all"],
            currentDirectory: snapshot.path
        )
        let changeCount = statusResult.stdoutString.split(whereSeparator: \.isNewline).count
        var stashCommit: String?

        if changeCount > 0 {
            guard strategy == .stashThenRemove else { throw WorktreeCleanupError.dirty(changeCount) }
            guard snapshot.pullRequest.isMergedAtCurrentHead else {
                throw WorktreeCleanupError.stashRequiresMergedPullRequest
            }

            let previousStash = stashOID(in: snapshot.path)
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let branch = snapshot.branch ?? snapshot.displayName
            _ = try runner.run(
                executable: "/usr/bin/git",
                arguments: [
                    "stash", "push", "--include-untracked",
                    "--message", "Prune cleanup backup: \(branch) at \(timestamp)"
                ],
                currentDirectory: snapshot.path
            )

            let currentStash = stashOID(in: snapshot.path)
            let postStashStatus = try runner.run(
                executable: "/usr/bin/git",
                arguments: ["status", "--porcelain=v1", "--untracked-files=all"],
                currentDirectory: snapshot.path
            )
            guard let currentStash,
                  currentStash != previousStash,
                  postStashStatus.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorktreeCleanupError.stashIncomplete
            }
            stashCommit = currentStash
        }

        guard let main = worktrees.first,
              !main.isBare,
              FileManager.default.fileExists(atPath: main.path) else {
            throw WorktreeCleanupError.mainCheckoutUnavailable
        }

        do {
            _ = try runner.run(
                executable: "/usr/bin/git",
                arguments: ["worktree", "remove", "--", snapshot.path.path],
                currentDirectory: URL(fileURLWithPath: main.path)
            )
        } catch {
            if let stashCommit {
                throw WorktreeCleanupError.removalFailedAfterStash(
                    commit: String(stashCommit.prefix(12)),
                    reason: error.localizedDescription
                )
            }
            throw error
        }

        guard !FileManager.default.fileExists(atPath: snapshot.path.path) else {
            throw WorktreeCleanupError.removalIncomplete
        }

        return CleanupResult(
            removedPath: snapshot.path,
            estimatedReclaimedBytes: snapshot.sizeBytes,
            stashCommit: stashCommit
        )
    }

    private func stashOID(in path: URL) -> String? {
        guard let result = try? runner.run(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "--verify", "refs/stash"],
            currentDirectory: path
        ) else { return nil }
        let value = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
