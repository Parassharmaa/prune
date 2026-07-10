import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scan folders")
                .font(.headline)
            Text("Prune finds Git repositories and their registered worktrees inside these folders.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                if store.roots.isEmpty {
                    ContentUnavailableView(
                        "No scan folders",
                        systemImage: "folder.badge.plus",
                        description: Text("Add one or more folders containing your Git repositories.")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(store.roots, id: \.path) { root in
                        Label(root.path, systemImage: "folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .onDelete(perform: store.removeRoots)
                }
            }
            .frame(minHeight: 180)

            HStack {
                Button("Add Folder…", action: chooseFolder)
                Spacer()
                Button("Refresh Now") { store.refresh() }
                    .disabled(store.phase == .scanning)
            }
        }
        .padding(20)
        .frame(width: 520, height: 320)
        .background(SettingsWindowActivationView())
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"

        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(store.addRoot)
    }
}

private struct SettingsWindowActivationView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsActivationNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SettingsActivationNSView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.title = "Prune Settings"
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
