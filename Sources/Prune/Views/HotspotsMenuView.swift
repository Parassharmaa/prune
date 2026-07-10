import AppKit
import SwiftUI

struct HotspotsMenuView: View {
    @EnvironmentObject private var store: DiskHotspotStore
    @Environment(\.openSettings) private var openSettings
    @State private var pendingCleanupID: String?

    private var isScanning: Bool { store.phase == .scanning }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.hotspots.isEmpty {
                VStack(spacing: 10) {
                    if isScanning { ProgressView() }
                    Image(systemName: isScanning ? "internaldrive" : "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isScanning ? Color.secondary : Color.green)
                    Text(isScanning ? "Looking for reclaimable space…" : "No cleanup hotspots found")
                        .font(.callout.weight(.medium))
                    Text(isScanning ? "Safe areas appear as soon as they are discovered." : "Prune found no eligible items in its guarded locations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        hotspotSectionHeader
                        ForEach(store.hotspots) { hotspot in
                            HotspotRow(
                                hotspot: hotspot,
                                isScanning: isScanning || store.isAutoCleanupRunning || store.cleaningID != nil,
                                isCleaning: store.isCleaning(hotspot),
                                isConfirming: pendingCleanupID == hotspot.id || store.isCleaning(hotspot),
                                cleanupError: pendingCleanupID == hotspot.id ? store.cleanupError : nil,
                                reveal: { store.reveal(hotspot) },
                                requestCleanup: {
                                    store.prepareCleanup()
                                    pendingCleanupID = hotspot.id
                                },
                                cancelCleanup: { pendingCleanupID = nil },
                                confirmCleanup: {
                                    Task {
                                        if await store.clean(hotspot) { pendingCleanupID = nil }
                                    }
                                }
                            )
                            .padding(.horizontal, 16)
                            .id(hotspot.id)
                            Divider().padding(.leading, 48)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Disk hotspots", systemImage: "internaldrive.fill")
                    .font(.headline)
                Spacer()
                Button(action: store.refresh) {
                    if isScanning { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .pruneGlassButton()
                .controlSize(.small)
                .disabled(isScanning || store.cleaningID != nil)
                .help("Refresh hotspots")
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ByteCountFormatter.string(fromByteCount: store.totalSizeBytes, countStyle: .file))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("across \(store.hotspots.count) disk hotspot\(store.hotspots.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.safelyReclaimableBytes > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ByteCountFormatter.string(fromByteCount: store.safelyReclaimableBytes, countStyle: .file))
                            .font(.headline)
                        Text("safe")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(12)
            .pruneGlassCard()

            if isScanning, !store.hotspots.isEmpty {
                Text("Found \(store.hotspots.count) · measured \(store.measuredCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if case .failed(let message) = store.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let notice = store.cleanupNotice {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(2)
                    Spacer()
                    Button(action: store.dismissNotice) { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
    }

    private var hotspotSectionHeader: some View {
        HStack(spacing: 8) {
            Text("Largest first")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            if store.isAutoCleanupRunning { ProgressView().controlSize(.mini) }
            Toggle(
                "Safe auto",
                isOn: Binding(
                    get: { store.isAutoCleanupEnabled },
                    set: { store.setAutoCleanupEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(store.isAutoCleanupRunning || store.cleaningID != nil)
            .help("Automatically clean only aged, re-creatable developer caches after a fresh scan. Downloads, Trash, app caches, and logs are never automatic.")
            .accessibilityIdentifier("disk-auto-cleanup-toggle")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 7)
    }

    private var footer: some View {
        HStack {
            if let date = store.lastRefreshed {
                Text("Updated \(date, style: .relative) ago")
            } else {
                Text("Not scanned yet")
            }
            Spacer()
            Button(action: showSettings) { Image(systemName: "gearshape") }
                .buttonStyle(.plain)
                .help("Settings")
                .accessibilityLabel("Settings")
            Divider().frame(height: 14)
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.plain)
                .help("Quit Prune")
                .accessibilityLabel("Quit Prune")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func showSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
    }
}
