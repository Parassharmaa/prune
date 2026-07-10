import Foundation

enum DiskCleanupSafety: String, Hashable, Sendable {
    case safe
    case review
    case managed

    var label: String {
        switch self {
        case .safe: "Safe"
        case .review: "Review"
        case .managed: "Tool-managed"
        }
    }
}

struct DiskHotspot: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case xcodeDerivedData
        case simulatorCaches
        case applicationCaches
        case homebrewDownloads
        case oldLogs
        case trash
        case oldInstallers
        case dockerData
        case pnpmStore
        case npmCache
        case gradleCache
        case developerCache
    }

    let kind: Kind
    let title: String
    let detail: String
    let consequence: String
    let systemImage: String
    let root: URL
    let targets: [URL]
    let safety: DiskCleanupSafety
    let isAutoCleanupEligible: Bool
    let sizeBytes: Int64?

    var id: String { kind.rawValue }
    var canClean: Bool { safety != .managed && !targets.isEmpty }

    func replacingSize(_ sizeBytes: Int64?) -> DiskHotspot {
        DiskHotspot(
            kind: kind,
            title: title,
            detail: detail,
            consequence: consequence,
            systemImage: systemImage,
            root: root,
            targets: targets,
            safety: safety,
            isAutoCleanupEligible: isAutoCleanupEligible,
            sizeBytes: sizeBytes
        )
    }
}

struct DiskCleanupResult: Sendable {
    let removedItemCount: Int
    let estimatedReclaimedBytes: Int64?
}
