import Foundation

protocol DiskHotspotCleaning: Sendable {
    func clean(_ hotspot: DiskHotspot) throws -> DiskCleanupResult
}

enum DiskHotspotCleanupError: LocalizedError {
    case unsafeRoot
    case unsafeTarget(URL)
    case empty

    var errorDescription: String? {
        switch self {
        case .unsafeRoot: "Prune refused to clean an unrecognized folder."
        case .unsafeTarget(let url): "Prune refused to delete an item outside the approved hotspot: \(url.path)"
        case .empty: "There is nothing left to clean in this hotspot."
        }
    }
}

struct DiskHotspotCleanupExecutor: DiskHotspotCleaning {
    private let home: URL

    init(home: URL? = nil) {
        self.home = (home ?? FileManager.default.homeDirectoryForCurrentUser).standardizedFileURL
    }

    func clean(_ hotspot: DiskHotspot) throws -> DiskCleanupResult {
        let root = hotspot.root.standardizedFileURL
        guard allowedRoots.contains(root) else { throw DiskHotspotCleanupError.unsafeRoot }

        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let targets = hotspot.targets.map(\.standardizedFileURL)
        guard !targets.isEmpty else { throw DiskHotspotCleanupError.empty }
        for target in targets {
            guard target != root, target.path.hasPrefix(rootPrefix) else {
                throw DiskHotspotCleanupError.unsafeTarget(target)
            }
        }

        var removed = 0
        for target in targets where FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
            removed += 1
        }
        guard removed > 0 else { throw DiskHotspotCleanupError.empty }
        return DiskCleanupResult(removedItemCount: removed, estimatedReclaimedBytes: hotspot.sizeBytes)
    }

    private var allowedRoots: Set<URL> {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        return [
            library.appendingPathComponent("Developer/Xcode/DerivedData", isDirectory: true),
            library.appendingPathComponent("Developer/CoreSimulator/Caches", isDirectory: true),
            library.appendingPathComponent("Caches", isDirectory: true),
            library.appendingPathComponent("Caches/Homebrew/downloads", isDirectory: true),
            library.appendingPathComponent("Logs", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true),
            home.appendingPathComponent(".Trash", isDirectory: true)
        ].map(\.standardizedFileURL).reduce(into: Set<URL>()) { $0.insert($1) }
    }
}
