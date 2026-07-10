import AppKit
import SwiftUI

struct WorktreeRow: View {
    let worktree: WorktreeSnapshot
    let isScanning: Bool
    let isRemoving: Bool
    let isConfirmingCleanup: Bool
    let cleanupError: String?
    let installedIDEs: [InstalledIDE]
    let reveal: () -> Void
    let openInIDE: (InstalledIDE) -> Void
    let cleanUp: () -> Void
    let cancelCleanup: () -> Void
    let confirmCleanup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: worktree.isMain ? "shield.fill" : stateIcon)
                    .foregroundStyle(worktree.isMain ? .secondary : stateColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(worktree.displayName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if worktree.isMain {
                            Text("MAIN")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    Text(worktree.branchDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if worktree.isMain {
                            Text(worktree.localState.title)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(worktree.pullRequest.label)
                                .foregroundStyle(pullRequestColor)
                            if !worktree.localState.isLocallyRemovable {
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text(worktree.localState.title)
                                    .foregroundStyle(stateColor)
                            }
                        }
                    }
                    .font(.caption2)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(sizeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Menu {
                            Button("Reveal in Finder", systemImage: "folder", action: reveal)
                            if !installedIDEs.isEmpty {
                                Menu("Open in", systemImage: "chevron.left.forwardslash.chevron.right") {
                                    ForEach(installedIDEs) { ide in
                                        Button(ide.name) { openInIDE(ide) }
                                    }
                                }
                            }
                            if let pullRequestURL {
                                Button("Open Pull Request", systemImage: "arrow.up.right.square") {
                                    NSWorkspace.shared.open(pullRequestURL)
                                }
                            }
                            Divider()
                            if worktree.isMain {
                                Button("Main checkout protected", systemImage: "shield") {}
                                    .disabled(true)
                            } else {
                                Button("Clean Up Manually…", systemImage: "trash", action: cleanUp)
                                    .disabled(!worktree.localState.isLocallyRemovable || isScanning || isRemoving)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 18)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("More actions")

                        if worktree.isCleanupCandidate, !isConfirmingCleanup {
                            Button(cleanupButtonTitle, action: cleanUp)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isScanning || isRemoving)
                                .help("Review and remove this worktree")
                                .accessibilityIdentifier("cleanup-\(worktree.displayName)")
                        }
                    }
                }
            }

            if isConfirmingCleanup {
                inlineConfirmation
            }
        }
        .padding(.vertical, 6)
        .help(worktree.localState.detail ?? "")
        .accessibilityIdentifier("worktree-row-\(worktree.displayName)")
    }

    private var inlineConfirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isRemoving {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(worktree.canStashAndClean ? "Stashing and cleaning up…" : "Cleaning up…")
                            .font(.callout.weight(.semibold))
                        Text("Removing \(worktree.displayName) safely with Git")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(sizeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("cleanup-loading-\(worktree.displayName)")
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Remove this worktree?")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(sizeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(confirmationDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let cleanupError {
                    Label(cleanupError, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("Cancel", action: cancelCleanup)
                        .controlSize(.small)
                        .accessibilityIdentifier("cancel-cleanup-\(worktree.displayName)")
                    Button(worktree.canStashAndClean ? "Stash & Remove" : "Remove", action: confirmCleanup)
                        .pruneDestructiveButton()
                        .controlSize(.small)
                        .accessibilityIdentifier("confirm-cleanup-\(worktree.displayName)")
                }
            }
        }
        .padding(10)
        .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.red.opacity(0.18), lineWidth: 0.5)
        }
        .accessibilityIdentifier("cleanup-confirmation-\(worktree.displayName)")
    }

    private var sizeText: String {
        guard let size = worktree.sizeBytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private var confirmationDetail: String {
        if worktree.canStashAndClean {
            return "The pull request is merged. Prune will stash all local and untracked changes first, verify the checkout is clean, then remove only this worktree."
        }
        if worktree.isReadyToClean {
            return "The pull request is merged and the worktree is clean. The branch stays; only this checkout is removed."
        }
        return "This is a manual cleanup because the pull request is not confirmed merged. The branch stays; only this checkout is removed."
    }

    private var cleanupButtonTitle: String {
        worktree.canStashAndClean ? "Stash & Clean Up" : "Clean Up"
    }

    private var pullRequestURL: URL? {
        switch worktree.pullRequest {
        case .open(_, _, let url, _), .merged(_, let url, _, _), .closed(_, let url, _): url
        default: nil
        }
    }

    private var pullRequestColor: Color {
        switch worktree.pullRequest {
        case .merged(_, _, _, true): .green
        case .open(_, let isDraft, _, _): isDraft ? .secondary : .blue
        case .closed: .orange
        case .merged(_, _, _, false): .orange
        case .unavailable: .orange
        case .checking, .notFound, .notApplicable: .secondary
        }
    }

    private var stateIcon: String {
        switch worktree.localState {
        case .clean: "checkmark.circle.fill"
        case .dirty: "pencil.circle.fill"
        case .locked: "lock.circle.fill"
        case .prunable, .missing: "exclamationmark.triangle.fill"
        case .mainCheckout: "shield.fill"
        }
    }

    private var stateColor: Color {
        switch worktree.localState {
        case .clean: .green
        case .dirty: .orange
        case .locked, .prunable, .missing: .red
        case .mainCheckout: .secondary
        }
    }
}
