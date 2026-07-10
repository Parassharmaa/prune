#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
mkdir -p .build

swiftc \
  Sources/Prune/Core/ScanRootDefaults.swift \
  Sources/Prune/Core/WorktreeSnapshot.swift \
  Sources/Prune/Core/WorktreePorcelainParser.swift \
  Sources/Prune/Services/CommandRunner.swift \
  Sources/Prune/Services/WorktreeDiscovery.swift \
  Sources/Prune/Services/GitHubPullRequestProvider.swift \
  Sources/Prune/Services/WorktreeScanner.swift \
  Sources/Prune/Services/WorktreeCleanupExecutor.swift \
  Tests/SelfTest/main.swift \
  -o .build/prune-self-test

.build/prune-self-test
