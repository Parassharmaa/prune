import AppKit
import Foundation

@MainActor
final class AppStore: ObservableObject {
    struct ScanProgress: Equatable {
        var discovered = 0
        var measured = 0
    }

    enum ScanPhase: Equatable {
        case idle
        case scanning
        case failed(String)
    }

    @Published private(set) var worktrees: [WorktreeSnapshot] = []
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var scanProgress = ScanProgress()
    @Published private(set) var displayOrderIDs: [String] = []
    @Published private(set) var displayReadyIDs: Set<String> = []
    @Published private(set) var removingWorktreeID: String?
    @Published private(set) var cleanupError: String?
    @Published private(set) var cleanupNotice: String?
    @Published private(set) var installedIDEs: [InstalledIDE] = []
    @Published private(set) var ideLaunchError: String?
    @Published private(set) var isAutoCleanupEnabled: Bool
    @Published private(set) var isAutoCleanupRunning = false
    @Published var roots: [URL] {
        didSet { persistRoots() }
    }

    private let scanner: WorktreeScanner
    private let cleanupExecutor: any WorktreeCleanupExecuting
    private let pullRequestProvider: GitHubPullRequestProvider
    private let defaults: UserDefaults
    private let refreshesAfterCleanup: Bool
    private var hasStarted = false
    private var scanTask: Task<Void, Never>?
    private var pendingDisplayOrderIDs: [String]?
    private var pendingDisplayReadyIDs: Set<String>?

    init(
        scanner: WorktreeScanner = WorktreeScanner(),
        cleanupExecutor: any WorktreeCleanupExecuting = WorktreeCleanupExecutor(),
        pullRequestProvider: GitHubPullRequestProvider = GitHubPullRequestProvider(),
        defaults: UserDefaults = .standard,
        initialWorktrees: [WorktreeSnapshot] = [],
        automaticallyStartsScanning: Bool = true,
        refreshesAfterCleanup: Bool = true
    ) {
        self.scanner = scanner
        self.cleanupExecutor = cleanupExecutor
        self.pullRequestProvider = pullRequestProvider
        self.defaults = defaults
        self.refreshesAfterCleanup = refreshesAfterCleanup
        self.isAutoCleanupEnabled = defaults.bool(forKey: "autoCleanupEnabled")
        self.roots = Self.loadRoots(from: defaults)
        self.worktrees = initialWorktrees
        self.displayOrderIDs = Self.finalDisplayOrder(for: initialWorktrees)
        self.displayReadyIDs = Set(initialWorktrees.filter(\.isCleanupCandidate).map(\.id))
        self.installedIDEs = IDEIntegration.detectInstalled()
        self.hasStarted = !automaticallyStartsScanning
    }

    var linkedWorktrees: [WorktreeSnapshot] { worktrees.filter(\.isLinked) }

    var readyToCleanWorktrees: [WorktreeSnapshot] {
        orderedForDisplay(
            worktrees.filter { displayReadyIDs.contains($0.id) }
        )
    }

    var otherWorktrees: [WorktreeSnapshot] {
        orderedForDisplay(
            worktrees.filter { !displayReadyIDs.contains($0.id) }
        )
    }

    var linkedSizeBytes: Int64 {
        linkedWorktrees.compactMap(\.sizeBytes).reduce(0, +)
    }

    var cleanLinkedSizeBytes: Int64 {
        linkedWorktrees
            .filter(\.isCleanupCandidate)
            .compactMap(\.sizeBytes)
            .reduce(0, +)
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        refresh()
    }

    func refresh() {
        guard phase != .scanning else { return }
        let roots = roots
        let scanner = scanner
        phase = .scanning
        scanProgress = ScanProgress()

        scanTask = Task { [weak self] in
            guard let self else { return }
            var seenIDs = Set<String>()
            do {
                for try await event in scanner.events(roots: roots) {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case .discovered(let snapshot):
                        seenIDs.insert(snapshot.id)
                        if let index = worktrees.firstIndex(where: { $0.id == snapshot.id }) {
                            let cachedSize = worktrees[index].sizeBytes
                            worktrees[index] = snapshot.replacingSize(cachedSize)
                        } else {
                            worktrees.append(snapshot)
                        }
                        if !displayOrderIDs.contains(snapshot.id) {
                            displayOrderIDs.append(snapshot.id)
                        }
                        scanProgress.discovered = seenIDs.count

                    case .sizeUpdated(let id, let sizeBytes):
                        if let index = worktrees.firstIndex(where: { $0.id == id }) {
                            if let sizeBytes {
                                worktrees[index] = worktrees[index].replacingSize(sizeBytes)
                            }
                            scanProgress.measured += 1
                        }

                    case .pullRequestUpdated(let id, let status):
                        if let index = worktrees.firstIndex(where: { $0.id == id }) {
                            let updated = worktrees[index].replacingPullRequest(status)
                            worktrees[index] = updated
                            if updated.isCleanupCandidate {
                                displayReadyIDs.insert(id)
                            } else {
                                displayReadyIDs.remove(id)
                            }
                        }

                    case .finished:
                        break
                    }
                }
                worktrees.removeAll { !seenIDs.contains($0.id) }
                pendingDisplayOrderIDs = Self.finalDisplayOrder(for: worktrees)
                pendingDisplayReadyIDs = Set(worktrees.filter(\.isCleanupCandidate).map(\.id))
                lastRefreshed = Date()
                phase = .idle
                scanTask = nil
                await runAutomaticCleanupIfNeeded()
            } catch {
                phase = .failed(error.localizedDescription)
                scanTask = nil
            }
        }
    }

    func addRoot(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard !roots.contains(normalized) else { return }
        roots.append(normalized)
        refresh()
    }

    func removeRoots(at offsets: IndexSet) {
        roots.remove(atOffsets: offsets)
        refresh()
    }

    func reveal(_ worktree: WorktreeSnapshot) {
        NSWorkspace.shared.activateFileViewerSelecting([worktree.path])
    }

    func open(_ worktree: WorktreeSnapshot, in ide: InstalledIDE) {
        ideLaunchError = nil
        Task {
            do {
                try await IDEIntegration.open(worktree.path, in: ide)
            } catch {
                ideLaunchError = "Could not open \(worktree.displayName) in \(ide.name): \(error.localizedDescription)"
            }
        }
    }

    func dismissIDELaunchError() {
        ideLaunchError = nil
    }

    func prepareCleanup() {
        cleanupError = nil
    }

    func isRemoving(_ worktree: WorktreeSnapshot) -> Bool {
        removingWorktreeID == worktree.id
    }

    func remove(_ worktree: WorktreeSnapshot) async -> Bool {
        await remove(
            worktree,
            refreshAfterRemoval: refreshesAfterCleanup,
            showsIndividualNotice: true
        )
    }

    func setAutoCleanupEnabled(_ enabled: Bool) {
        isAutoCleanupEnabled = enabled
        defaults.set(enabled, forKey: "autoCleanupEnabled")
        if enabled, phase != .scanning {
            Task { await runAutomaticCleanupIfNeeded() }
        }
    }

    private func remove(
        _ worktree: WorktreeSnapshot,
        refreshAfterRemoval: Bool,
        showsIndividualNotice: Bool
    ) async -> Bool {
        guard removingWorktreeID == nil else { return false }
        guard phase != .scanning else {
            cleanupError = "Wait for the current scan to finish, then try again."
            return false
        }

        removingWorktreeID = worktree.id
        cleanupError = nil
        if showsIndividualNotice { cleanupNotice = nil }
        let cleanupExecutor = cleanupExecutor
        let strategy: CleanupStrategy = worktree.canStashAndClean ? .stashThenRemove : .removeClean

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try cleanupExecutor.remove(worktree, strategy: strategy)
            }.value
            removingWorktreeID = nil
            worktrees.removeAll { $0.id == worktree.id }
            displayOrderIDs.removeAll { $0 == worktree.id }
            displayReadyIDs.remove(worktree.id)
            pendingDisplayOrderIDs?.removeAll { $0 == worktree.id }
            pendingDisplayReadyIDs?.remove(worktree.id)
            let reclaimed = result.estimatedReclaimedBytes.map {
                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
            }
            let stashNote = result.stashCommit == nil ? "" : " Local changes were saved in Git stash."
            if showsIndividualNotice {
                cleanupNotice = reclaimed.map { "Removed \(worktree.displayName) and reclaimed about \($0).\(stashNote)" }
                    ?? "Removed \(worktree.displayName).\(stashNote)"
            }
            if refreshAfterRemoval { refresh() }
            return true
        } catch {
            removingWorktreeID = nil
            cleanupError = error.localizedDescription
            return false
        }
    }

    private func runAutomaticCleanupIfNeeded() async {
        guard isAutoCleanupEnabled,
              !isAutoCleanupRunning,
              removingWorktreeID == nil else { return }

        let candidates = worktrees.filter(\.isReadyToClean)
        guard !candidates.isEmpty else { return }

        isAutoCleanupRunning = true
        defer { isAutoCleanupRunning = false }
        var removedCount = 0
        var reclaimedBytes: Int64 = 0
        let pullRequestProvider = pullRequestProvider

        for candidate in candidates {
            guard isAutoCleanupEnabled else { break }
            let freshStatus = await Task.detached(priority: .userInitiated) {
                pullRequestProvider.status(for: candidate)
            }.value
            let refreshed = candidate.replacingPullRequest(freshStatus)

            if let index = worktrees.firstIndex(where: { $0.id == candidate.id }) {
                worktrees[index] = refreshed
            }
            guard refreshed.isReadyToClean else {
                displayReadyIDs.remove(candidate.id)
                continue
            }

            if await remove(
                refreshed,
                refreshAfterRemoval: false,
                showsIndividualNotice: false
            ) {
                removedCount += 1
                reclaimedBytes += refreshed.sizeBytes ?? 0
            }
        }

        if removedCount > 0 {
            let reclaimed = ByteCountFormatter.string(fromByteCount: reclaimedBytes, countStyle: .file)
            cleanupNotice = "Auto-cleaned \(removedCount) worktree\(removedCount == 1 ? "" : "s") and reclaimed about \(reclaimed)."
            if refreshesAfterCleanup { refresh() }
        }
    }

    func dismissCleanupNotice() {
        cleanupNotice = nil
    }

    func applyPendingDisplayOrder() {
        guard let pendingDisplayOrderIDs else { return }
        displayOrderIDs = pendingDisplayOrderIDs
        if let pendingDisplayReadyIDs {
            displayReadyIDs = pendingDisplayReadyIDs
        }
        self.pendingDisplayOrderIDs = nil
        self.pendingDisplayReadyIDs = nil
    }

    private func persistRoots() {
        defaults.set(roots.map(\.path), forKey: "scanRoots")
    }

    private func orderedForDisplay(_ candidates: [WorktreeSnapshot]) -> [WorktreeSnapshot] {
        let rank = Dictionary(uniqueKeysWithValues: displayOrderIDs.enumerated().map { ($1, $0) })
        return candidates.sorted { lhs, rhs in
            let leftRank = rank[lhs.id] ?? Int.max
            let rightRank = rank[rhs.id] ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            return Self.largerWorktreeFirst(lhs, rhs)
        }
    }

    private static func finalDisplayOrder(for worktrees: [WorktreeSnapshot]) -> [String] {
        let ready = worktrees
            .filter(\.isCleanupCandidate)
            .sorted(by: largerWorktreeFirst)
        let other = worktrees
            .filter { !$0.isCleanupCandidate }
            .sorted(by: largerWorktreeFirst)
        return (ready + other).map(\.id)
    }

    private static func largerWorktreeFirst(_ lhs: WorktreeSnapshot, _ rhs: WorktreeSnapshot) -> Bool {
        let leftSize = lhs.sizeBytes ?? -1
        let rightSize = rhs.sizeBytes ?? -1
        if leftSize != rightSize { return leftSize > rightSize }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }

    private static func loadRoots(from defaults: UserDefaults) -> [URL] {
        defaults.stringArray(forKey: "scanRoots")?
            .map { URL(fileURLWithPath: $0).standardizedFileURL } ?? []
    }
}
