import AppKit
import Foundation

@MainActor
final class DiskHotspotStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case failed(String)
    }

    @Published private(set) var hotspots: [DiskHotspot]
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var measuredCount = 0
    @Published private(set) var cleaningID: String?
    @Published private(set) var cleanupError: String?
    @Published private(set) var cleanupNotice: String?
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var isAutoCleanupEnabled: Bool
    @Published private(set) var isAutoCleanupRunning = false

    private let scanner: DiskHotspotScanner
    private let cleanupExecutor: any DiskHotspotCleaning
    private let defaults: UserDefaults
    private let home: URL
    private let rechecksBeforeAutoCleanup: Bool
    private var hasStarted = false
    private var scanTask: Task<Void, Never>?

    init(
        scanner: DiskHotspotScanner = DiskHotspotScanner(),
        cleanupExecutor: any DiskHotspotCleaning = DiskHotspotCleanupExecutor(),
        defaults: UserDefaults = .standard,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        initialHotspots: [DiskHotspot] = [],
        automaticallyStartsScanning: Bool = true,
        rechecksBeforeAutoCleanup: Bool = true
    ) {
        self.scanner = scanner
        self.cleanupExecutor = cleanupExecutor
        self.defaults = defaults
        self.home = home.standardizedFileURL
        self.hotspots = initialHotspots.sorted(by: Self.sortHotspots)
        self.rechecksBeforeAutoCleanup = rechecksBeforeAutoCleanup
        self.isAutoCleanupEnabled = defaults.bool(forKey: "autoDiskCleanupEnabled")
        self.hasStarted = !automaticallyStartsScanning
        self.lastRefreshed = initialHotspots.isEmpty ? nil : Date()
    }

    var totalSizeBytes: Int64 { hotspots.compactMap(\.sizeBytes).reduce(0, +) }
    var safelyReclaimableBytes: Int64 {
        hotspots.filter { $0.safety == .safe }.compactMap(\.sizeBytes).reduce(0, +)
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        refresh()
    }

    func refresh() {
        guard phase != .scanning, cleaningID == nil else { return }
        phase = .scanning
        measuredCount = 0
        let scanner = scanner
        let home = home
        scanTask = Task { [weak self] in
            guard let self else { return }
            var seen = Set<String>()
            do {
                for try await event in scanner.events(home: home) {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case .discovered(let hotspot):
                        seen.insert(hotspot.id)
                        if let index = hotspots.firstIndex(where: { $0.id == hotspot.id }) {
                            hotspots[index] = hotspot.replacingSize(hotspots[index].sizeBytes)
                        } else {
                            hotspots.append(hotspot)
                        }
                    case .sizeUpdated(let id, let size):
                        if let index = hotspots.firstIndex(where: { $0.id == id }) {
                            hotspots[index] = hotspots[index].replacingSize(size)
                            measuredCount += 1
                        }
                    case .finished:
                        break
                    }
                }
                hotspots.removeAll { !seen.contains($0.id) }
                hotspots.sort(by: Self.sortHotspots)
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

    func reveal(_ hotspot: DiskHotspot) {
        NSWorkspace.shared.activateFileViewerSelecting([hotspot.root])
    }

    func prepareCleanup() { cleanupError = nil }
    func isCleaning(_ hotspot: DiskHotspot) -> Bool { cleaningID == hotspot.id }
    func dismissNotice() { cleanupNotice = nil }

    func clean(_ hotspot: DiskHotspot) async -> Bool {
        await clean(hotspot, showsNotice: true)
    }

    func setAutoCleanupEnabled(_ enabled: Bool) {
        isAutoCleanupEnabled = enabled
        defaults.set(enabled, forKey: "autoDiskCleanupEnabled")
        if enabled, phase != .scanning {
            Task { await runAutomaticCleanupIfNeeded() }
        }
    }

    private func clean(_ hotspot: DiskHotspot, showsNotice: Bool) async -> Bool {
        guard cleaningID == nil, phase != .scanning else { return false }
        cleaningID = hotspot.id
        cleanupError = nil
        let executor = cleanupExecutor
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try executor.clean(hotspot)
            }.value
            cleaningID = nil
            hotspots.removeAll { $0.id == hotspot.id }
            if showsNotice {
                let size = result.estimatedReclaimedBytes.map {
                    ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                } ?? "disk space"
                cleanupNotice = "Cleaned \(hotspot.title) and reclaimed about \(size)."
            }
            return true
        } catch {
            cleaningID = nil
            cleanupError = error.localizedDescription
            return false
        }
    }

    private func runAutomaticCleanupIfNeeded() async {
        guard isAutoCleanupEnabled, !isAutoCleanupRunning, cleaningID == nil else { return }
        let fresh: [DiskHotspot]
        if rechecksBeforeAutoCleanup {
            let scanner = scanner
            let home = home
            fresh = await Task.detached(priority: .utility) {
                scanner.scan(home: home).filter(\.isAutoCleanupEligible)
            }.value
        } else {
            fresh = hotspots.filter(\.isAutoCleanupEligible)
        }
        guard !fresh.isEmpty else { return }
        isAutoCleanupRunning = true
        defer { isAutoCleanupRunning = false }
        var count = 0
        var bytes: Int64 = 0
        for hotspot in fresh where isAutoCleanupEnabled {
            if await clean(hotspot, showsNotice: false) {
                count += 1
                bytes += hotspot.sizeBytes ?? 0
            }
        }
        if count > 0 {
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            cleanupNotice = "Auto-cleaned \(count) safe hotspot\(count == 1 ? "" : "s") and reclaimed about \(size)."
        }
    }

    private static func sortHotspots(_ lhs: DiskHotspot, _ rhs: DiskHotspot) -> Bool {
        let left = lhs.sizeBytes ?? -1
        let right = rhs.sizeBytes ?? -1
        if left != right { return left > right }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
