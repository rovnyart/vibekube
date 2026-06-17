import Foundation

struct KubernetesExecLaunchRequest: Equatable, Sendable {
    var contextName: String
    var namespace: String
    var podName: String
    var containerName: String?
    var command: [String]
    var kubeconfigPath: String?
}

protocol KubernetesExecLaunching {
    nonisolated func launchExec(request: KubernetesExecLaunchRequest) async throws
}

struct TerminalKubernetesExecLauncher: KubernetesExecLaunching {
    private let runner: TerminalCommandRunning

    init(runner: TerminalCommandRunning = AppleScriptTerminalCommandRunner()) {
        self.runner = runner
    }

    nonisolated func launchExec(request: KubernetesExecLaunchRequest) async throws {
        try await runner.run(command: Self.shellCommand(for: request))
    }

    nonisolated static func shellCommand(for request: KubernetesExecLaunchRequest) -> String {
        var segments = [
            "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
        ]
        if let kubeconfigPath = request.kubeconfigPath, !kubeconfigPath.isEmpty {
            segments.append("export KUBECONFIG=\(shellQuoted(kubeconfigPath))")
        }

        var arguments = [
            "kubectl",
            "--context",
            request.contextName,
            "-n",
            request.namespace,
            "exec",
            "-it",
            request.podName
        ]

        if let containerName = request.containerName, !containerName.isEmpty {
            arguments += ["-c", containerName]
        }

        arguments.append("--")
        arguments += request.command.isEmpty ? ["/bin/sh"] : request.command
        segments.append(arguments.map(shellQuoted).joined(separator: " "))
        return segments.joined(separator: "; ")
    }

    private nonisolated static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

protocol TerminalCommandRunning {
    nonisolated func run(command: String) async throws
}

struct AppleScriptTerminalCommandRunner: TerminalCommandRunning {
    nonisolated func run(command: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"Terminal\" to activate",
            "-e",
            "tell application \"Terminal\" to do script \(appleScriptStringLiteral(command))"
        ]

        let stderr = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardError = stderr
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw KubernetesExecLaunchError.startFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        let status = process.terminationStatus
        guard status == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw KubernetesExecLaunchError.startFailed(
                message.isEmpty ? "osascript exited with code \(status)" : message
            )
        }
    }

    private nonisolated func appleScriptStringLiteral(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

enum KubernetesExecLaunchError: Error, LocalizedError, Equatable {
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .startFailed(let message):
            "Exec terminal could not be opened: \(message)"
        }
    }
}
