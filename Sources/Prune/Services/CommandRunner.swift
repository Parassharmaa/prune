import Foundation

struct CommandResult: Sendable {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32

    var stdoutString: String {
        String(data: stdout, encoding: .utf8) ?? ""
    }

    var stderrString: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }
}

enum CommandError: LocalizedError {
    case launchFailed(executable: String, underlying: Error)
    case failed(executable: String, arguments: [String], result: CommandResult)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let executable, let underlying):
            return "Could not launch \(executable): \(underlying.localizedDescription)"
        case .failed(let executable, let arguments, let result):
            let detail = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(executable) \(arguments.joined(separator: " ")) failed (\(result.exitCode))\(detail.isEmpty ? "" : ": \(detail)")"
        }
    }
}

protocol CommandRunning: Sendable {
    func run(executable: String, arguments: [String], currentDirectory: URL?) throws -> CommandResult
}

struct SystemCommandRunner: CommandRunning {
    func run(executable: String, arguments: [String], currentDirectory: URL? = nil) throws -> CommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed(executable: executable, underlying: error)
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let result = CommandResult(
            stdout: outputData,
            stderr: errorData,
            exitCode: process.terminationStatus
        )
        guard result.exitCode == 0 else {
            throw CommandError.failed(executable: executable, arguments: arguments, result: result)
        }
        return result
    }
}
