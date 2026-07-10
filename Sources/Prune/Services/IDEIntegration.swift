import AppKit
import Foundation

struct InstalledIDE: Identifiable, Hashable, Sendable {
    let name: String
    let bundleIdentifier: String
    let applicationURL: URL

    var id: String { bundleIdentifier }
}

@MainActor
enum IDEIntegration {
    private struct Definition {
        let name: String
        let bundleIdentifier: String
    }

    private static let definitions = [
        Definition(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode"),
        Definition(name: "Visual Studio Code Insiders", bundleIdentifier: "com.microsoft.VSCodeInsiders"),
        Definition(name: "Zed", bundleIdentifier: "dev.zed.Zed"),
        Definition(name: "Zed Preview", bundleIdentifier: "dev.zed.Zed-Preview"),
        Definition(name: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92")
    ]

    static func detectInstalled(workspace: NSWorkspace = .shared) -> [InstalledIDE] {
        definitions.compactMap { definition in
            guard let applicationURL = workspace.urlForApplication(
                withBundleIdentifier: definition.bundleIdentifier
            ) else { return nil }
            return InstalledIDE(
                name: definition.name,
                bundleIdentifier: definition.bundleIdentifier,
                applicationURL: applicationURL
            )
        }
    }

    static func open(_ folder: URL, in ide: InstalledIDE) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open(
            [folder],
            withApplicationAt: ide.applicationURL,
            configuration: configuration
        )
    }
}
