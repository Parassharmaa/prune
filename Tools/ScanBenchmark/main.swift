import Foundation

@main
struct ScanBenchmark {
    static func main() async throws {
        let roots = CommandLine.arguments.dropFirst().map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        guard !roots.isEmpty else {
            fputs("Usage: prune-scan-benchmark <scan-root> [...]\n", stderr)
            exit(2)
        }

        let started = Date()
        var discovered = 0
        var measured = 0
        var firstDiscovery: TimeInterval?

        for try await event in WorktreeScanner().events(roots: roots) {
            switch event {
            case .discovered(let snapshot):
                discovered += 1
                if firstDiscovery == nil {
                    firstDiscovery = Date().timeIntervalSince(started)
                }
                print("discovered \(snapshot.displayName)")
            case .sizeUpdated:
                measured += 1
            case .finished:
                break
            }
        }

        let total = Date().timeIntervalSince(started)
        print(String(format: "first_item=%.2fs total=%.2fs discovered=%d measured=%d", firstDiscovery ?? total, total, discovered, measured))
    }
}
