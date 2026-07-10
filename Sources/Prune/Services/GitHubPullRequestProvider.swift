import Foundation

struct GitHubPullRequestProvider: Sendable {
    private struct PullRequest: Decodable, Sendable {
        let number: Int
        let state: String
        let isDraft: Bool
        let mergedAt: String?
        let url: URL
        let title: String
        let headRefOid: String
        let updatedAt: String
    }

    private let runner: any CommandRunning
    private let executable: String?

    init(
        runner: any CommandRunning = SystemCommandRunner(),
        executable: String? = GitHubPullRequestProvider.findExecutable()
    ) {
        self.runner = runner
        self.executable = executable
    }

    func status(for snapshot: WorktreeSnapshot) -> PullRequestStatus {
        guard snapshot.isLinked, let branch = snapshot.branch else { return .notApplicable }
        guard let executable else { return .unavailable(reason: "GitHub CLI is not installed.") }

        do {
            let repositoryResult = try runner.run(
                executable: executable,
                arguments: ["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
                currentDirectory: snapshot.path
            )
            let repository = repositoryResult.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !repository.isEmpty else { return .unavailable(reason: "Could not resolve the GitHub repository.") }

            let result = try runner.run(
                executable: executable,
                arguments: [
                    "pr", "list", "--repo", repository,
                    "--head", branch, "--state", "all", "--limit", "20",
                    "--json", "number,state,isDraft,mergedAt,url,title,headRefOid,updatedAt"
                ],
                currentDirectory: snapshot.path
            )
            let pullRequests = try JSONDecoder().decode([PullRequest].self, from: result.stdout)
            guard let selected = selectPullRequest(pullRequests, head: snapshot.head) else { return .notFound }

            if selected.mergedAt != nil || selected.state.uppercased() == "MERGED" {
                return .merged(
                    number: selected.number,
                    url: selected.url,
                    title: selected.title,
                    headMatches: selected.headRefOid == snapshot.head
                )
            }
            if selected.state.uppercased() == "OPEN" {
                return .open(
                    number: selected.number,
                    isDraft: selected.isDraft,
                    url: selected.url,
                    title: selected.title
                )
            }
            return .closed(number: selected.number, url: selected.url, title: selected.title)
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
    }

    private func selectPullRequest(_ pullRequests: [PullRequest], head: String?) -> PullRequest? {
        if let exact = pullRequests.first(where: { $0.headRefOid == head }) { return exact }
        if let open = pullRequests.first(where: { $0.state.uppercased() == "OPEN" }) { return open }
        return pullRequests.sorted { $0.updatedAt > $1.updatedAt }.first
    }

    private static func findExecutable() -> String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
