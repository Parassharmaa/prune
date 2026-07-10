# Inline cleanup E2E scenario

This scenario runs Prune's real SwiftUI lists and cleanup interactions with deterministic sample hotspots, sample worktrees, and non-destructive cleanup executors.

## Launch

```sh
scripts/run-e2e-sample.sh
```

## Assertions

### Disk hotspots

1. **Hotspots** is the default section and reports `28.1 GB` across five fixture-only rows.
2. Docker is labelled **Tool-managed · Inspect only** and has no raw deletion action.
3. Xcode build data and Homebrew downloads are labelled **Safe · Auto eligible**.
4. Application caches and downloaded installers are labelled **Review · Confirm first**.
5. Clicking **Clean Up** expands the row inline without closing the window.
6. The confirmation explains the consequence and shows **Cancel** plus **Delete & Reclaim**.
7. Confirming shows a progress indicator and disables other cleanup actions while the fake executor runs.
8. Only the selected fixture row disappears and the reclaimed-space notice is shown.
9. Turning on **Safe auto** can remove only the two Safe fixtures; Review and Tool-managed fixtures remain.
10. Switching to **Worktrees** preserves the original worktree interface and assertions below.

### Worktrees

1. `atlas-merged-auth` is the first row under **Ready to clean** and displays `PR #142 merged`.
2. `atlas-merged-local` is also Ready, displays its local-change count, and offers **Stash & Clean Up**.
3. Clicking the clean fixture's **Clean Up** button keeps the Prune window open.
4. The same row expands inline with:
   - `Remove this worktree?`
   - the GitHub-status warning;
   - **Cancel** and **Remove** buttons.
5. Clicking **Cancel** collapses the inline confirmation and preserves the row.
6. Clicking **Clean Up**, then **Remove**, removes only `atlas-merged-auth`.
7. While removal runs, the row shows **Cleaning up…** with a progress indicator and no active cleanup actions.
8. The success notice reports about `8.6 GB` reclaimed.
9. The stash-backed fixture shows **Stash & Remove** inline and **Stashing and cleaning up…** while running.
10. `atlas-old-dashboard` remains under **Other worktrees** with `PR #143 open` and a three-dot manual cleanup option.
11. The dirty draft worktree displays its PR plus `3 local changes`; manual cleanup is disabled.
12. The protected main checkout remains and cannot be cleaned as a linked worktree.

The sample executor never launches Git and cannot delete a real folder.

## Auto cleanup assertion

1. Turn on **Auto** beside Ready to clean.
2. The clean merged fixture is removed after its PR is rechecked.
3. The merged fixture with local changes remains and still offers **Stash & Clean Up**.
4. The notice reports one automatically removed worktree.
