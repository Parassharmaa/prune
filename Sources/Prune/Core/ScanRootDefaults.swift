import Foundation

enum ScanRootDefaults {
    static let storageKey = "scanRoots"

    static func load(
        from defaults: UserDefaults,
        fileManager: FileManager = .default
    ) -> [URL] {
        if defaults.object(forKey: storageKey) != nil {
            return unique(
                defaults.stringArray(forKey: storageKey)?
                    .map { URL(fileURLWithPath: $0).standardizedFileURL } ?? []
            )
        }

        return suggested(fileManager: fileManager)
    }

    static func suggested(fileManager: FileManager = .default) -> [URL] {
        let standardFolders: [FileManager.SearchPathDirectory] = [
            .desktopDirectory,
            .documentDirectory,
            .downloadsDirectory
        ]
        let folders = [fileManager.homeDirectoryForCurrentUser] + standardFolders.compactMap {
            fileManager.urls(for: $0, in: .userDomainMask).first
        }
        return unique(folders.map(\.standardizedFileURL))
    }

    private static func unique(_ roots: [URL]) -> [URL] {
        var seen = Set<URL>()
        return roots.filter { seen.insert($0).inserted }
    }
}
