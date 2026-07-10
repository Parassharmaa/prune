import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openSettings) private var openSettings
    @State private var pendingCleanupID: String?

    private var isScanning: Bool { store.phase == .scanning }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.worktrees.isEmpty {
                if isScanning {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Looking for worktrees…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("Choose scan folders", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Prune scans only folders you explicitly select.")
                    } actions: {
                        Button("Open Settings", action: showSettings)
                            .pruneGlassButton(prominent: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                    sectionHeader("Ready to clean", showsAutoCleanup: true)
                    if !store.readyToCleanWorktrees.isEmpty {
                        ForEach(store.readyToCleanWorktrees) { worktree in
                            worktreeRow(worktree)
                            Divider().padding(.leading, 48)
                        }
                    } else {
                        Text(isScanning ? "Checking pull requests…" : "No clean merged worktrees")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    if !store.otherWorktrees.isEmpty {
                        sectionHeader("Other worktrees")
                        ForEach(store.otherWorktrees) { worktree in
                            worktreeRow(worktree)
                            Divider().padding(.leading, 48)
                        }
                    }
                    }
                }
                .scrollIndicators(.visible)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }

            Divider()
            footer
        }
        .frame(width: 400, height: 520)
        .task { store.startIfNeeded() }
        .onDisappear { store.applyPendingDisplayOrder() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Prune", systemImage: "leaf.fill")
                    .font(.headline)
                Spacer()
                Button {
                    store.refresh()
                } label: {
                    if isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .pruneGlassButton()
                .controlSize(.small)
                .disabled(isScanning)
                .help("Refresh")
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ByteCountFormatter.string(fromByteCount: store.linkedSizeBytes, countStyle: .file))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("in \(store.linkedWorktrees.count) linked worktree\(store.linkedWorktrees.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.cleanLinkedSizeBytes > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ByteCountFormatter.string(fromByteCount: store.cleanLinkedSizeBytes, countStyle: .file))
                            .font(.headline)
                        Text("ready")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .pruneGlassCard()

            if case .failed(let message) = store.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            if isScanning, store.scanProgress.discovered > 0 {
                Text("Found \(store.scanProgress.discovered) · measured \(store.scanProgress.measured)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let notice = store.cleanupNotice {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button {
                        store.dismissCleanupNotice()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
            }

            if let error = store.ideLaunchError {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button {
                        store.dismissIDELaunchError()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            if let date = store.lastRefreshed {
                Text("Updated \(date, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not scanned yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showSettings()
            } label: {
                Image(systemName: "gearshape")
            }
                .buttonStyle(.plain)
                .help("Settings")
                .accessibilityLabel("Settings")
            Divider().frame(height: 14)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
                .buttonStyle(.plain)
                .help("Quit Prune")
                .accessibilityLabel("Quit Prune")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func worktreeRow(_ worktree: WorktreeSnapshot) -> some View {
        WorktreeRow(
            worktree: worktree,
            isScanning: isScanning || store.isAutoCleanupRunning,
            isRemoving: store.isRemoving(worktree),
            isConfirmingCleanup: pendingCleanupID == worktree.id,
            cleanupError: pendingCleanupID == worktree.id ? store.cleanupError : nil,
            installedIDEs: store.installedIDEs,
            reveal: { store.reveal(worktree) },
            openInIDE: { ide in store.open(worktree, in: ide) },
            cleanUp: {
                store.prepareCleanup()
                pendingCleanupID = worktree.id
            },
            cancelCleanup: { pendingCleanupID = nil },
            confirmCleanup: {
                Task {
                    if await store.remove(worktree) {
                        pendingCleanupID = nil
                    }
                }
            }
        )
        .padding(.horizontal, 16)
        .id("\(worktree.id)|\(worktree.pullRequest.label)")
    }

    private func showSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func sectionHeader(_ title: String, showsAutoCleanup: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            if showsAutoCleanup {
                if store.isAutoCleanupRunning {
                    ProgressView()
                        .controlSize(.mini)
                }
                Toggle(
                    "Auto",
                    isOn: Binding(
                        get: { store.isAutoCleanupEnabled },
                        set: { store.setAutoCleanupEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(store.isAutoCleanupRunning)
                .help("Automatically remove only locally clean worktrees whose PR is merged at the current HEAD. Local changes are never auto-stashed.")
                .accessibilityIdentifier("auto-cleanup-toggle")
            }
        }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
