import AppKit
import SwiftUI

@MainActor
final class PruneAppDelegate: NSObject, NSApplicationDelegate {
    private var e2eWindow: NSWindow?
    private var e2eStore: AppStore?
    private var e2eDiskStore: DiskHotspotStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--e2e-window") else { return }

        let usesSampleData = arguments.contains("--sample-data")
        let store = usesSampleData ? PruneSampleData.makeStore() : AppStore()
        let diskStore = usesSampleData ? PruneSampleData.makeDiskStore() : DiskHotspotStore()
        let rootView = MenuBarView()
            .environmentObject(store)
            .environmentObject(diskStore)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = usesSampleData ? "Prune E2E Sample" : "Prune E2E Live Scan"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 400, height: 560))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        e2eStore = store
        e2eDiskStore = diskStore
        e2eWindow = window

        if arguments.contains("--enable-auto-cleanup") {
            store.setAutoCleanupEnabled(true)
            diskStore.setAutoCleanupEnabled(true)
        }
    }
}

@main
struct PruneApp: App {
    @NSApplicationDelegateAdaptor(PruneAppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @StateObject private var diskStore = DiskHotspotStore()

    var body: some Scene {
        MenuBarExtra("Prune", systemImage: "leaf") {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(diskStore)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
