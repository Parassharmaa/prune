# Inline cleanup E2E scenario

This scenario runs Prune's real SwiftUI list and cleanup interaction with deterministic sample worktrees and a non-destructive cleanup executor.

## Launch

```sh
scripts/run-e2e-sample.sh
```

## Assertions

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
