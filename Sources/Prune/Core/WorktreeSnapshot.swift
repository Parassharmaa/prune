import Foundation

enum PullRequestStatus: Hashable, Sendable {
    case notApplicable
    case checking
    case notFound
    case open(number: Int, isDraft: Bool, url: URL, title: String)
    case merged(number: Int, url: URL, title: String, headMatches: Bool)
    case closed(number: Int, url: URL, title: String)
    case unavailable(reason: String)

    var isMergedAtCurrentHead: Bool {
        if case .merged(_, _, _, let headMatches) = self { return headMatches }
        return false
    }

    var label: String {
        switch self {
        case .notApplicable: "No PR check"
        case .checking: "Checking GitHub…"
        case .notFound: "No pull request"
        case .open(let number, let isDraft, _, _): isDraft ? "PR #\(number) draft" : "PR #\(number) open"
        case .merged(let number, _, _, let headMatches): headMatches ? "PR #\(number) merged" : "PR #\(number) merged · new commits"
        case .closed(let number, _, _): "PR #\(number) closed"
        case .unavailable: "GitHub unavailable"
        }
    }
}

struct WorktreeSnapshot: Identifiable, Hashable, Sendable {
    enum LocalState: Hashable, Sendable {
        case mainCheckout
        case clean
        case dirty(changeCount: Int)
        case locked(reason: String?)
        case prunable(reason: String)
        case missing

        var title: String {
            switch self {
            case .mainCheckout: "Protected"
            case .clean: "Clean"
            case .dirty(let count): "\(count) local change\(count == 1 ? "" : "s")"
            case .locked: "Locked"
            case .prunable: "Broken metadata"
            case .missing: "Missing"
            }
        }

        var detail: String? {
            switch self {
            case .mainCheckout:
                "Main checkouts are never removable."
            case .clean:
                "No local changes detected."
            case .dirty(let count):
                "Git reports \(count) modified, staged, deleted, or untracked item\(count == 1 ? "" : "s"). Commit, stash, or remove them first."
            case .locked(let reason):
                reason ?? "Git has locked this worktree."
            case .prunable(let reason):
                reason
            case .missing:
                "The registered worktree path does not exist."
            }
        }

        var isLocallyRemovable: Bool {
            if case .clean = self { true } else { false }
        }
    }

    let repositoryName: String
    let commonGitDirectory: URL
    let path: URL
    let head: String?
    let branch: String?
    let isMain: Bool
    let sizeBytes: Int64?
    let localState: LocalState
    let pullRequest: PullRequestStatus

    init(
        repositoryName: String,
        commonGitDirectory: URL,
        path: URL,
        head: String?,
        branch: String?,
        isMain: Bool,
        sizeBytes: Int64?,
        localState: LocalState,
        pullRequest: PullRequestStatus? = nil
    ) {
        self.repositoryName = repositoryName
        self.commonGitDirectory = commonGitDirectory
        self.path = path
        self.head = head
        self.branch = branch
        self.isMain = isMain
        self.sizeBytes = sizeBytes
        self.localState = localState
        self.pullRequest = pullRequest ?? (isMain ? .notApplicable : .checking)
    }

    var id: String { path.standardizedFileURL.path }
    var displayName: String { path.lastPathComponent }
    var branchDisplayName: String { branch ?? "Detached HEAD" }
    var isLinked: Bool { !isMain }
    var isReadyToClean: Bool { isLinked && localState.isLocallyRemovable && pullRequest.isMergedAtCurrentHead }
    var canStashAndClean: Bool {
        guard isLinked, pullRequest.isMergedAtCurrentHead else { return false }
        if case .dirty = localState { return true }
        return false
    }
    var isCleanupCandidate: Bool { isReadyToClean || canStashAndClean }

    func replacingSize(_ sizeBytes: Int64?) -> WorktreeSnapshot {
        WorktreeSnapshot(
            repositoryName: repositoryName,
            commonGitDirectory: commonGitDirectory,
            path: path,
            head: head,
            branch: branch,
            isMain: isMain,
            sizeBytes: sizeBytes,
            localState: localState,
            pullRequest: pullRequest
        )
    }

    func replacingPullRequest(_ pullRequest: PullRequestStatus) -> WorktreeSnapshot {
        WorktreeSnapshot(
            repositoryName: repositoryName,
            commonGitDirectory: commonGitDirectory,
            path: path,
            head: head,
            branch: branch,
            isMain: isMain,
            sizeBytes: sizeBytes,
            localState: localState,
            pullRequest: pullRequest
        )
    }
}

struct ParsedWorktree: Equatable, Sendable {
    var path: String
    var head: String?
    var branch: String?
    var isBare = false
    var isDetached = false
    var lockedReason: String?
    var prunableReason: String?
}
