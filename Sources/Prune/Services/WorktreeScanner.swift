import Foundation

enum WorktreeScanEvent: Sendable {
    case discovered(WorktreeSnapshot)
    case sizeUpdated(id: String, sizeBytes: Int64?)
    case pullRequestUpdated(id: String, status: PullRequestStatus)
    case finished
}

struct WorktreeScanner: Sendable {
    private let runner: any CommandRunning
    private let discovery: WorktreeDiscovery
    private let pullRequestProvider: GitHubPullRequestProvider
    private let maximumConcurrentSizeScans = 3
    private let maximumConcurrentPullRequestChecks = 4

    init(
        runner: any CommandRunning = SystemCommandRunner(),
        pullRequestProvider: GitHubPullRequestProvider? = nil
    ) {
        self.runner = runner
        self.discovery = WorktreeDiscovery(runner: runner)
        self.pullRequestProvider = pullRequestProvider ?? GitHubPullRequestProvider(runner: runner)
    }

    /// The app consumes this stream so metadata appears before slower disk-size work finishes.
    func events(roots: [URL]) -> AsyncThrowingStream<WorktreeScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task.detached(priority: .utility) {
                do {
                    let snapshots = try scanMetadata(roots: roots) { snapshot in
                        continuation.yield(.discovered(snapshot))
                    }
                    try Task.checkCancellation()

                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            await emitSizeUpdates(for: snapshots, continuation: continuation)
                        }
                        group.addTask {
                            await emitPullRequestUpdates(for: snapshots, continuation: continuation)
                        }
                    }

                    try Task.checkCancellation()
                    continuation.yield(.finished)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    private func emitSizeUpdates(
        for snapshots: [WorktreeSnapshot],
        continuation: AsyncThrowingStream<WorktreeScanEvent, Error>.Continuation
    ) async {
        await withTaskGroup(of: (String, Int64?).self) { group in
            var pending = snapshots.makeIterator()

            for _ in 0..<min(maximumConcurrentSizeScans, snapshots.count) {
                guard let snapshot = pending.next() else { break }
                _ = group.addTaskUnlessCancelled {
                    (snapshot.id, sizeOfDirectory(snapshot.path))
                }
            }

            while let (id, size) = await group.next() {
                continuation.yield(.sizeUpdated(id: id, sizeBytes: size))
                if let snapshot = pending.next() {
                    _ = group.addTaskUnlessCancelled {
                        (snapshot.id, sizeOfDirectory(snapshot.path))
                    }
                }
            }
        }
    }

    private func emitPullRequestUpdates(
        for snapshots: [WorktreeSnapshot],
        continuation: AsyncThrowingStream<WorktreeScanEvent, Error>.Continuation
    ) async {
        let linked = snapshots.filter { $0.isLinked && $0.branch != nil }
        await withTaskGroup(of: (String, PullRequestStatus).self) { group in
            var pending = linked.makeIterator()

            for _ in 0..<min(maximumConcurrentPullRequestChecks, linked.count) {
                guard let snapshot = pending.next() else { break }
                _ = group.addTaskUnlessCancelled {
                    (snapshot.id, pullRequestProvider.status(for: snapshot))
                }
            }

            while let (id, status) = await group.next() {
                continuation.yield(.pullRequestUpdated(id: id, status: status))
                if let snapshot = pending.next() {
                    _ = group.addTaskUnlessCancelled {
                        (snapshot.id, pullRequestProvider.status(for: snapshot))
                    }
                }
            }
        }
    }

    /// Synchronous entry point used by the dependency-free integration checks.
    func scan(roots: [URL]) throws -> [WorktreeSnapshot] {
        try scanMetadata(roots: roots).map { snapshot in
            snapshot.replacingSize(sizeOfDirectory(snapshot.path))
        }
    }

    /// Discovers and inspects local Git state without waiting for directory-size calculation.
    func scanMetadata(
        roots: [URL],
        onDiscovered: (WorktreeSnapshot) -> Void = { _ in }
    ) throws -> [WorktreeSnapshot] {
        var seenCommonDirectories = Set<URL>()
        var snapshots: [WorktreeSnapshot] = []

        try discovery.forEachRepositorySeed(in: roots) { seed in
            try Task.checkCancellation()
            guard let commonDirectory = commonGitDirectory(for: seed),
                  seenCommonDirectories.insert(commonDirectory).inserted else { return }

            let result = try runner.run(
                executable: "/usr/bin/git",
                arguments: ["worktree", "list", "--porcelain", "-z"],
                currentDirectory: seed
            )
            let parsed = WorktreePorcelainParser.parse(result.stdout)
            let repositoryName = repositoryName(commonGitDirectory: commonDirectory, fallback: seed)

            for (index, worktree) in parsed.enumerated() where !worktree.isBare {
                try Task.checkCancellation()
                let path = URL(fileURLWithPath: worktree.path).standardizedFileURL
                let exists = FileManager.default.fileExists(atPath: path.path)
                let isMain = index == 0
                let snapshot = WorktreeSnapshot(
                    repositoryName: repositoryName,
                    commonGitDirectory: commonDirectory,
                    path: path,
                    head: worktree.head,
                    branch: worktree.branch,
                    isMain: isMain,
                    sizeBytes: nil,
                    localState: inspectLocalState(
                        worktree: worktree,
                        path: path,
                        exists: exists,
                        isMain: isMain
                    )
                )
                snapshots.append(snapshot)
                onDiscovered(snapshot)
            }
        }

        return snapshots.sorted {
            if $0.repositoryName != $1.repositoryName {
                return $0.repositoryName.localizedStandardCompare($1.repositoryName) == .orderedAscending
            }
            if $0.isMain != $1.isMain { return $0.isMain }
            return $0.path.path.localizedStandardCompare($1.path.path) == .orderedAscending
        }
    }

    private func commonGitDirectory(for seed: URL) -> URL? {
        guard let result = try? runner.run(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"],
            currentDirectory: seed
        ) else { return nil }

        let path = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private func inspectLocalState(
        worktree: ParsedWorktree,
        path: URL,
        exists: Bool,
        isMain: Bool
    ) -> WorktreeSnapshot.LocalState {
        guard exists else {
            if let reason = worktree.prunableReason { return .prunable(reason: reason) }
            return .missing
        }
        if isMain { return .mainCheckout }
        if let reason = worktree.lockedReason {
            return .locked(reason: reason.isEmpty ? nil : reason)
        }
        if let reason = worktree.prunableReason { return .prunable(reason: reason) }

        guard let result = try? runner.run(
            executable: "/usr/bin/git",
            arguments: ["status", "--porcelain=v1", "--untracked-files=all"],
            currentDirectory: path
        ) else {
            return .dirty(changeCount: 1)
        }

        let count = result.stdoutString.split(whereSeparator: \.isNewline).count
        return count == 0 ? .clean : .dirty(changeCount: count)
    }

    private func sizeOfDirectory(_ path: URL) -> Int64? {
        guard FileManager.default.fileExists(atPath: path.path),
              let result = try? runner.run(
                  executable: "/usr/bin/du",
                  arguments: ["-sk", path.path],
                  currentDirectory: nil
              ) else { return nil }

        guard let firstField = result.stdoutString.split(whereSeparator: \.isWhitespace).first,
              let kilobytes = Int64(firstField) else { return nil }
        return kilobytes * 1_024
    }

    private func repositoryName(commonGitDirectory: URL, fallback: URL) -> String {
        if commonGitDirectory.lastPathComponent == ".git" {
            return commonGitDirectory.deletingLastPathComponent().lastPathComponent
        }
        return fallback.lastPathComponent
    }
}
