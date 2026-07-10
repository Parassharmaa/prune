# Disk cleanup rubric

Prune classifies a hotspot before offering deletion. A large folder is not automatically waste.

## Decision rubric

| Signal | Safe | Review | Tool-managed / never automatic |
| --- | --- | --- | --- |
| Source of truth | Re-created or downloaded again | May contain useful diagnostic or downloaded data | Stores with their own lifecycle, plus documents, projects, archives, backups, photos, mail, and messages |
| Scope | Exact user-owned allowlisted cache root | Exact user-owned Trash, Downloads, cache, or log root | Docker, package-manager stores, system folders, and arbitrary paths |
| Age | Unmodified for at least 30 days | Unmodified for at least 30 days, or explicitly placed in Trash | Any age; the owning tool decides reachability |
| Cleanup | Delete only enumerated descendants | Inline consequence plus explicit confirmation | Inspect in Prune; clean with the owning tool |
| Automation | Opt-in and freshly rescanned | Never | Never |

Additional guards:

- the allowlisted root itself is never removed;
- descendants are standardized and containment-checked immediately before deletion;
- symlinks are excluded from scanning;
- automation is off by default;
- application caches, logs, Downloads, and Trash always require confirmation;
- worktrees retain their separate Git and GitHub-aware protections.

## Initial hotspot coverage

- Xcode Derived Data untouched for 30 days;
- CoreSimulator caches untouched for 30 days;
- application cache folders untouched for 30 days;
- Homebrew downloads untouched for 30 days;
- diagnostic logs untouched for 30 days;
- Trash contents;
- old `.dmg`, `.pkg`, `.xip`, and `.zip` files in Downloads.
- Docker Desktop data, pnpm and npm stores, Gradle caches, and `~/.cache` as inspect-only tool-managed hotspots.

## Why tool-managed stores are separate

Docker volumes can contain databases, pnpm uses a shared content-addressable store, and developer caches can contain large models or managed runtimes. Direct folder deletion loses the owning tool's reachability information. Prune therefore reports their size and location but does not offer raw deletion. Future command-aware actions must show the tool's own dry-run/reclaimable result before confirmation.

The audit that motivated this rule found Docker reporting its own reclaimable subset, which was materially smaller than Docker's total backing-directory size. Total size must not be presented as safely reclaimable space.

## Research basis

- Apple recommends using macOS Storage settings to inspect categories, reviewing Downloads, removing unused apps or media, and emptying Trash to reclaim space: <https://support.apple.com/en-us/102624>
- Apple notes that safe mode can clear certain system caches and that those caches are created again as needed: <https://support.apple.com/en-us/102624>
- Apple's file-system guidance describes cache data as data an app does not require to operate correctly and can improve performance: <https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html>
- Homebrew documents `brew cleanup` as removing stale lock files and outdated downloads: <https://docs.brew.sh/Manpage#cleanup-options-formula-cask>
- Docker provides `docker system df` to inspect daemon disk usage and a separate `docker system prune` command whose volume behavior must be chosen explicitly: <https://docs.docker.com/reference/cli/docker/system/df/> and <https://docs.docker.com/reference/cli/docker/system/prune/>
- pnpm documents `pnpm store prune` as removing packages that are not referenced by any projects on the system: <https://pnpm.io/cli/store>
