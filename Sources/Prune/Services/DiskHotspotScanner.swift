import Foundation

enum DiskHotspotScanEvent: Sendable {
    case discovered(DiskHotspot)
    case sizeUpdated(id: String, sizeBytes: Int64?)
    case finished
}

struct DiskHotspotScanner: Sendable {
    private let runner: any CommandRunning
    private let fixedNow: Date?
    private let minimumAge: TimeInterval

    init(
        runner: any CommandRunning = SystemCommandRunner(),
        now: Date? = nil,
        minimumAge: TimeInterval = 30 * 24 * 60 * 60
    ) {
        self.runner = runner
        self.fixedNow = now
        self.minimumAge = minimumAge
    }

    func events(home: URL) -> AsyncThrowingStream<DiskHotspotScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task.detached(priority: .utility) {
                do {
                    let candidates = candidates(home: home)
                    for candidate in candidates {
                        try Task.checkCancellation()
                        continuation.yield(.discovered(candidate))
                    }

                    await withTaskGroup(of: (String, Int64?).self) { group in
                        for candidate in candidates {
                            group.addTask {
                                (candidate.id, size(of: candidate.targets))
                            }
                        }
                        for await update in group {
                            continuation.yield(.sizeUpdated(id: update.0, sizeBytes: update.1))
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

    func scan(home: URL) -> [DiskHotspot] {
        candidates(home: home).map { $0.replacingSize(size(of: $0.targets)) }
    }

    func candidates(home: URL) -> [DiskHotspot] {
        let home = home.standardizedFileURL
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let cutoff = (fixedNow ?? Date()).addingTimeInterval(-minimumAge)

        let definitions: [(DiskHotspot.Kind, String, String, String, String, URL, DiskCleanupSafety, Bool, Set<String>?)] = [
            (
                .xcodeDerivedData,
                "Old Xcode build data",
                "Derived Data untouched for 30 days",
                "Xcode recreates this data during a future build.",
                "hammer.fill",
                library.appendingPathComponent("Developer/Xcode/DerivedData", isDirectory: true),
                .safe,
                true,
                nil
            ),
            (
                .simulatorCaches,
                "Old simulator caches",
                "CoreSimulator cache items untouched for 30 days",
                "Simulator support data may be regenerated when a simulator runs again.",
                "iphone.gen3",
                library.appendingPathComponent("Developer/CoreSimulator/Caches", isDirectory: true),
                .safe,
                true,
                nil
            ),
            (
                .applicationCaches,
                "Old application caches",
                "App cache folders untouched for 30 days",
                "Apps can recreate caches, but their next launch may be slower. Close apps first.",
                "shippingbox.fill",
                library.appendingPathComponent("Caches", isDirectory: true),
                .review,
                false,
                ["Homebrew"]
            ),
            (
                .homebrewDownloads,
                "Old Homebrew downloads",
                "Downloaded bottles and sources untouched for 30 days",
                "Homebrew downloads these packages again if they are needed.",
                "mug.fill",
                library.appendingPathComponent("Caches/Homebrew/downloads", isDirectory: true),
                .safe,
                true,
                nil
            ),
            (
                .oldLogs,
                "Old diagnostic logs",
                "Log folders untouched for 30 days",
                "Deleted logs cannot help diagnose older problems, but apps create new logs as needed.",
                "doc.text.magnifyingglass",
                library.appendingPathComponent("Logs", isDirectory: true),
                .review,
                false,
                nil
            ),
            (
                .trash,
                "Trash",
                "Items still occupying disk space",
                "This permanently deletes every listed Trash item and cannot be undone.",
                "trash.fill",
                home.appendingPathComponent(".Trash", isDirectory: true),
                .review,
                false,
                nil
            )
        ]

        var hotspots = definitions.compactMap { definition -> DiskHotspot? in
            let usesAgeFilter = definition.0 != .trash
            let targets = directChildren(
                of: definition.5,
                olderThan: usesAgeFilter ? cutoff : nil,
                excludingNames: definition.8 ?? []
            )
            guard !targets.isEmpty else { return nil }
            return DiskHotspot(
                kind: definition.0,
                title: definition.1,
                detail: definition.2,
                consequence: definition.3,
                systemImage: definition.4,
                root: definition.5,
                targets: targets,
                safety: definition.6,
                isAutoCleanupEligible: definition.7,
                sizeBytes: nil
            )
        }

        let installerExtensions = Set(["dmg", "pkg", "xip", "zip"])
        let installers = directChildren(of: downloads, olderThan: cutoff).filter {
            installerExtensions.contains($0.pathExtension.lowercased())
        }
        if !installers.isEmpty {
            hotspots.append(
                DiskHotspot(
                    kind: .oldInstallers,
                    title: "Old downloaded installers",
                    detail: "DMG, PKG, XIP, and ZIP files untouched for 30 days",
                    consequence: "These are user files. Confirm that you no longer need the installers before deleting them.",
                    systemImage: "arrow.down.circle.fill",
                    root: downloads,
                    targets: installers,
                    safety: .review,
                    isAutoCleanupEligible: false,
                    sizeBytes: nil
                )
            )
        }

        let managedDefinitions: [(DiskHotspot.Kind, String, String, String, String, URL)] = [
            (
                .dockerData,
                "Docker Desktop data",
                "Inspect reclaimable data with `docker system df`",
                "Use Docker's own prune commands so active containers and named volumes remain protected.",
                "shippingbox.and.arrow.backward.fill",
                library.appendingPathComponent("Containers/com.docker.docker", isDirectory: true)
            ),
            (
                .pnpmStore,
                "pnpm content store",
                "Run `pnpm store prune` for unreferenced packages",
                "Use `pnpm store prune` to remove unreferenced packages instead of deleting the store directly.",
                "shippingbox.circle.fill",
                library.appendingPathComponent("pnpm/store", isDirectory: true)
            ),
            (
                .npmCache,
                "npm cache",
                "Run `npm cache verify` before forced cleanup",
                "npm maintains cache integrity itself; inspect it with npm before forcing a full cache clean.",
                "shippingbox.circle",
                home.appendingPathComponent(".npm", isDirectory: true)
            ),
            (
                .gradleCache,
                "Gradle cache",
                "Review dependencies, wrappers, and stopped daemons",
                "Use Gradle-aware cleanup or remove selected old versions after stopping Gradle daemons.",
                "g.square.fill",
                home.appendingPathComponent(".gradle", isDirectory: true)
            ),
            (
                .developerCache,
                "Developer tool cache",
                "Review models and managed runtimes under ~/.cache",
                "Inspect the largest tool folders individually; this root can include models and runtimes that are expensive to download again.",
                "wrench.and.screwdriver.fill",
                home.appendingPathComponent(".cache", isDirectory: true)
            )
        ]

        for definition in managedDefinitions where fileManagerExists(definition.5) {
            hotspots.append(
                DiskHotspot(
                    kind: definition.0,
                    title: definition.1,
                    detail: definition.2,
                    consequence: definition.3,
                    systemImage: definition.4,
                    root: definition.5,
                    targets: [definition.5],
                    safety: .managed,
                    isAutoCleanupEligible: false,
                    sizeBytes: nil
                )
            )
        }

        return hotspots
    }

    private func fileManagerExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func directChildren(
        of root: URL,
        olderThan cutoff: Date?,
        excludingNames: Set<String> = []
    ) -> [URL] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isSymbolicLinkKey]
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return children.filter { child in
            guard !excludingNames.contains(child.lastPathComponent),
                  let values = try? child.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true else { return false }
            guard let cutoff else { return true }
            return (values.contentModificationDate ?? .distantPast) < cutoff
        }
    }

    private func size(of targets: [URL]) -> Int64? {
        var total: Int64 = 0
        var measured = false
        for target in targets {
            guard let result = try? runner.run(
                executable: "/usr/bin/du",
                arguments: ["-sk", target.path],
                currentDirectory: nil
            ), let field = result.stdoutString.split(whereSeparator: \.isWhitespace).first,
                  let kilobytes = Int64(field) else { continue }
            total += kilobytes * 1_024
            measured = true
        }
        return measured ? total : nil
    }
}
