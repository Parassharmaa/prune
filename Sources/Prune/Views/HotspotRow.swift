import SwiftUI

struct HotspotRow: View {
    let hotspot: DiskHotspot
    let isScanning: Bool
    let isCleaning: Bool
    let isConfirming: Bool
    let cleanupError: String?
    let reveal: () -> Void
    let requestCleanup: () -> Void
    let cancelCleanup: () -> Void
    let confirmCleanup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: hotspot.systemImage)
                    .foregroundStyle(safetyColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(hotspot.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(hotspot.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(safetyLabel)
                        .font(.caption2)
                        .foregroundStyle(safetyColor)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(sizeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Button(action: reveal) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain)
                        .help("Reveal hotspot in Finder")
                        if hotspot.canClean, !isConfirming {
                            Button("Clean Up", action: requestCleanup)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isScanning || isCleaning)
                                .accessibilityIdentifier("hotspot-cleanup-\(hotspot.kind.rawValue)")
                        }
                    }
                }
            }

            if isConfirming {
                confirmation
            }
        }
        .padding(.vertical, 7)
        .help(hotspot.consequence)
        .accessibilityIdentifier("hotspot-row-\(hotspot.kind.rawValue)")
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isCleaning {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Cleaning \(hotspot.title.lowercased())…")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(sizeText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("hotspot-cleanup-loading-\(hotspot.kind.rawValue)")
            } else {
                Label("Delete \(hotspot.targets.count) item\(hotspot.targets.count == 1 ? "" : "s")?", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(hotspot.safety == .safe ? Color.primary : Color.orange)
                Text(hotspot.consequence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let cleanupError {
                    Label(cleanupError, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Cancel", action: cancelCleanup).controlSize(.small)
                    Button("Delete & Reclaim \(sizeText)", action: confirmCleanup)
                        .pruneDestructiveButton()
                        .controlSize(.small)
                        .accessibilityIdentifier("hotspot-confirm-cleanup-\(hotspot.kind.rawValue)")
                }
            }
        }
        .padding(10)
        .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.red.opacity(0.18), lineWidth: 0.5)
        }
    }

    private var sizeText: String {
        hotspot.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
    }

    private var safetyLabel: String {
        if hotspot.isAutoCleanupEligible { return "Safe · Auto eligible" }
        if hotspot.safety == .managed { return "Tool-managed · Inspect only" }
        return "Review · Confirm first"
    }

    private var safetyColor: Color {
        switch hotspot.safety {
        case .safe: .green
        case .review: .orange
        case .managed: .blue
        }
    }
}
