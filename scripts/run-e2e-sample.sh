#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

scripts/build-app.sh debug >/dev/null
pkill -x Prune 2>/dev/null || true
open -n "$ROOT/.build/Prune.app" --args --sample-data --e2e-window

echo "Opened Prune E2E Sample with non-destructive fixture data."
