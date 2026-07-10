import Foundation

enum WorktreePorcelainParser {
    static func parse(_ data: Data) -> [ParsedWorktree] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: true)
        var result: [ParsedWorktree] = []
        var current: ParsedWorktree?

        for fieldData in fields {
            guard let field = String(data: fieldData, encoding: .utf8) else { continue }

            if field.hasPrefix("worktree ") {
                if let current { result.append(current) }
                current = ParsedWorktree(path: String(field.dropFirst("worktree ".count)))
                continue
            }

            guard current != nil else { continue }

            if field.hasPrefix("HEAD ") {
                current?.head = String(field.dropFirst("HEAD ".count))
            } else if field.hasPrefix("branch ") {
                let ref = String(field.dropFirst("branch ".count))
                current?.branch = ref.hasPrefix("refs/heads/")
                    ? String(ref.dropFirst("refs/heads/".count))
                    : ref
            } else if field == "bare" {
                current?.isBare = true
            } else if field == "detached" {
                current?.isDetached = true
            } else if field == "locked" {
                current?.lockedReason = ""
            } else if field.hasPrefix("locked ") {
                current?.lockedReason = String(field.dropFirst("locked ".count))
            } else if field.hasPrefix("prunable ") {
                current?.prunableReason = String(field.dropFirst("prunable ".count))
            }
        }

        if let current { result.append(current) }
        return result
    }
}
