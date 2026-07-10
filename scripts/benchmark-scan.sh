#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
mkdir -p .build

swiftc -parse-as-library \
  Sources/Prune/Core/WorktreeSnapshot.swift \
  Sources/Prune/Core/WorktreePorcelainParser.swift \
  Sources/Prune/Services/CommandRunner.swift \
  Sources/Prune/Services/WorktreeDiscovery.swift \
  Sources/Prune/Services/GitHubPullRequestProvider.swift \
  Sources/Prune/Services/WorktreeScanner.swift \
  Tools/ScanBenchmark/main.swift \
  -o .build/prune-scan-benchmark

.build/prune-scan-benchmark "$@"
