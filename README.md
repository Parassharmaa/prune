# Prune

**A native macOS menu bar app for finding disk hotspots and safely reclaiming space.**

Prune scans guarded, user-scoped storage areas for old generated data, explains the consequence of every cleanup, and keeps its original GitHub-aware worktree manager as a dedicated module.

<p align="center">
  <img src="docs/images/prune-sample.png" width="400" alt="Prune menu bar app showing fixture-only disk hotspots and cleanup actions">
</p>

> The screenshot uses deterministic fixture data. It contains no real paths, caches, downloads, repositories, or pull requests.

## Why Prune?

macOS exposes broad storage categories, but the large, hidden, and re-creatable folders under `~/Library` are still difficult to judge. Size alone is not enough: a cache, an archive, and a project can all be 10 GB with very different deletion risk.

Prune combines size with a safety rubric:

- generated cache vs. user-authored data;
- exact allowlisted location and containment checks;
- 30-day inactivity threshold;
- clear cleanup consequence and inline confirmation;
- opt-in automation only for freshly rescanned safe data.

## Highlights

- **Native macOS experience** — SwiftUI `MenuBarExtra`, Liquid Glass on macOS 26, and native material fallbacks on macOS 14–15.
- **Disk hotspots** — finds aged Xcode data, simulator caches, app caches, Homebrew downloads, logs, Trash, and old downloaded installers.
- **Tool-aware inspection** — surfaces Docker, pnpm, npm, Gradle, and `~/.cache` without offering unsafe raw deletion of their managed stores.
- **Progressive scanning** — hotspots and worktrees appear immediately while bounded background jobs calculate sizes.
- **Safety labels** — separates re-creatable **Safe** data from **Review** areas that always require confirmation.
- **Guarded deletion** — removes only previously enumerated descendants of user-scoped allowlisted roots; never the root itself.
- **Safe auto cleanup** — off by default and restricted to aged, re-creatable developer caches after a fresh scan.
- **Stable scrolling** — rows do not reorder or flicker while a sync is running.
- **GitHub-aware readiness** — a worktree becomes ready when its PR is merged at the checked-out `HEAD`.
- **Local-work protection** — modified, staged, deleted, and untracked files are always reported separately from PR state.
- **Stash & Clean Up** — merged worktrees with local changes can be backed up with `git stash --include-untracked` before removal.
- **Optional automation** — Auto cleanup rechecks GitHub and removes only locally clean merged-PR worktrees. It never auto-stashes.
- **Manual escape hatch** — clean linked worktrees without a merged PR can be reviewed from the three-dot menu.
- **Open anywhere** — detects installed copies of Visual Studio Code, Zed, and Cursor.
- **Main checkout protection** — the primary repository checkout is never treated as a removable worktree.

Prune never cleans arbitrary paths and never uses `git worktree remove --force`. The complete policy is in [`docs/DISK_CLEANUP_RUBRIC.md`](docs/DISK_CLEANUP_RUBRIC.md).

## Requirements

- macOS 14 or newer
- Apple Command Line Tools with Swift 6.2 or newer
- Git at `/usr/bin/git`
- [GitHub CLI](https://cli.github.com/) for pull-request status

Install and authenticate GitHub CLI if needed:

```sh
brew install gh
gh auth login
```

## Build and run

### Download

Every successful GitHub Actions run produces a universal **Prune-macOS** build for both Apple Silicon and Intel Macs. Open the run's **Artifacts** section, download it, extract `Prune-macOS.zip`, and move `Prune.app` to Applications.

Version tags automatically publish the same zip and its SHA-256 checksum on the [Releases page](https://github.com/Parassharmaa/prune/releases), providing a public download that does not expire with CI artifact retention.

The app is currently ad-hoc signed rather than notarized. On first launch, macOS may require **Control-click → Open**. Developer ID signing and notarization are planned before stable distribution.

### Build locally

```sh
git clone https://github.com/Parassharmaa/prune.git
cd prune

scripts/build-app.sh release
open .build/Prune.app
```

The build script creates an ad-hoc signed local app bundle. Full Xcode is not required for local development, but Developer ID signing and notarization will require it before distribution.

Create the same universal download archive used by CI:

```sh
scripts/package-app.sh
```

This writes `.build/dist/Prune-macOS.zip` and a matching `.sha256` checksum.

On first launch:

1. Prune saves your macOS **Home**, **Documents**, and **Downloads** locations as its initial scan folders.
2. Open **Settings** from the gear icon to add or remove scan folders.
3. These locations are resolved through macOS APIs—there are no machine-specific hardcoded filesystem paths.
4. Overlapping locations are scanned only once, and an intentionally empty folder list stays empty.
5. Authenticate `gh` if GitHub status is unavailable.

## Cleanup safety

### Disk hotspots

Prune scans only known folders inside the current user's home directory. Generated developer caches must be untouched for at least 30 days before becoming **Safe** and auto-eligible. Application caches, logs, Downloads, and Trash are labelled **Review**, never cleaned automatically, and show their consequences before an inline destructive confirmation.

Every cleanup revalidates that:

- the root exactly matches an allowlisted hotspot;
- the root itself is never a deletion target;
- every target remains a standardized descendant of that root;
- only targets captured by the scan are removed.

### Clean merged worktree

Prune rechecks Git registration, lock state, local status, submodules, and PR `HEAD`, then runs:

```sh
git worktree remove -- <path>
```

### Merged worktree with local changes

The explicit **Stash & Clean Up** flow:

1. creates a labelled stash including untracked files;
2. verifies that a new stash exists;
3. verifies that the checkout became clean;
4. removes the linked worktree;
5. keeps the local branch and recovery stash intact.

If removal fails after stashing, Prune reports the preserved stash commit.

### Auto cleanup

Auto is off by default and persisted locally. It runs only after a complete scan and only for worktrees that are:

- linked rather than main checkouts;
- locally clean;
- unlocked and structurally valid;
- associated with a merged PR at the exact current `HEAD`;
- freshly rechecked against GitHub immediately before removal.

Local changes are never stashed automatically.

## Development

Build the Swift package:

```sh
swift build
```

Run dependency-free integration checks:

```sh
scripts/test.sh
```

The tests create disposable home folders, repositories, and linked worktrees to verify hotspot aging and containment, outside-root rejection, parsing, main-checkout protection, dirty-state rejection, stash recovery, and clean removal.

Measure scan latency against a folder:

```sh
scripts/benchmark-scan.sh ~/Projects
```

## Safe native E2E fixtures

Launch the real SwiftUI interface with deterministic sample data and a fake cleanup backend:

```sh
scripts/run-e2e-sample.sh
```

Exercise auto cleanup against the same non-destructive backend:

```sh
scripts/run-e2e-auto-sample.sh
```

The assertions are documented in [`Tests/E2E/INLINE_CLEANUP.md`](Tests/E2E/INLINE_CLEANUP.md). Sample mode uses `/Sample/*` paths, cannot invoke Git, and cannot remove a real folder.

## Project structure

```text
App/                    App bundle metadata
Sources/Prune/App/      Application state and sample fixtures
Sources/Prune/Core/     Worktree and PR domain models
Sources/Prune/Services/ Git, GitHub, disk, cleanup, and IDE integrations
Sources/Prune/Views/    Native SwiftUI and Liquid Glass interface
Tests/SelfTest/         Dependency-free integration checks
Tests/E2E/              Native sample scenarios
Tools/                  Scan benchmarking utility
scripts/                Build, validation, and E2E commands
.github/workflows/      CI, universal packaging, and tagged releases
```

## Privacy

Prune runs locally. It does not upload file or repository contents and includes no analytics. Disk hotspots are restricted to documented user-scoped roots; worktree scan folders remain visible in Settings. GitHub status is queried through the user's existing authenticated `gh` session.

## Status

Prune is an early macOS utility under active development. Planned work includes background notifications, per-repository automation policies, grace periods, Developer ID signing, notarization, and automatic updates.
