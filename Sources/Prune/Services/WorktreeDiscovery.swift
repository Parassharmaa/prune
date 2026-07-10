import Foundation

struct WorktreeDiscovery: Sendable {
    private let runner: any CommandRunning

    private let skippedDirectoryNames: Set<String> = [
        ".Trash", ".cache", ".npm", ".pnpm-store", ".yarn", "Library",
        "Applications", "node_modules", "vendor", "DerivedData", ".build",
        "build", "dist", "target", "Pods", ".gradle", ".venv", "venv",
        "__pycache__", ".tox", "Caches"
    ]

    init(runner: any CommandRunning = SystemCommandRunner()) {
        self.runner = runner
    }

    func findRepositorySeeds(in roots: [URL]) -> [URL] {
        var seeds = Set<URL>()
        forEachRepositorySeed(in: roots) { seeds.insert($0) }
        return seeds.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func forEachRepositorySeed(
        in roots: [URL],
        _ visit: (URL) throws -> Void
    ) rethrows {
        let fileManager = FileManager.default
        var emittedSeeds = Set<URL>()

        for root in nonOverlappingRoots(roots) where fileManager.fileExists(atPath: root.path) {
            if isGitWorkingDirectory(root) {
                let seed = root.standardizedFileURL
                if emittedSeeds.insert(seed).inserted { try visit(seed) }
            }

            let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let item = enumerator.nextObject() as? URL {
                let name = item.lastPathComponent
                if skippedDirectoryNames.contains(name) || (name.hasPrefix(".") && name != ".git") {
                    enumerator.skipDescendants()
                    continue
                }

                if name == ".git" {
                    let seed = item.deletingLastPathComponent().standardizedFileURL
                    if emittedSeeds.insert(seed).inserted { try visit(seed) }
                    enumerator.skipDescendants()
                }
            }
        }
    }

    func groupByCommonGitDirectory(seeds: [URL]) -> [URL: URL] {
        var repositories: [URL: URL] = [:]

        for seed in seeds {
            guard let result = try? runner.run(
                executable: "/usr/bin/git",
                arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"],
                currentDirectory: seed
            ) else { continue }

            let path = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            let commonDirectory = URL(fileURLWithPath: path).standardizedFileURL
            repositories[commonDirectory] = repositories[commonDirectory] ?? seed
        }

        return repositories
    }

    private func isGitWorkingDirectory(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

    private func nonOverlappingRoots(_ roots: [URL]) -> [URL] {
        let normalized = Set(roots.map(\.standardizedFileURL))
            .sorted { $0.path.count < $1.path.count }
        var result: [URL] = []

        for candidate in normalized {
            let candidatePath = candidate.path.hasSuffix("/") ? candidate.path : candidate.path + "/"
            let isNested = result.contains { root in
                let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
                return candidatePath.hasPrefix(rootPath)
            }
            if !isNested { result.append(candidate) }
        }
        return result
    }
}
