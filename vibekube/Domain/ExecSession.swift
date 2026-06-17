import Foundation

struct KubernetesExecLaunchRequest: Equatable, Sendable {
    var contextName: String
    var namespace: String
    var podName: String
    var containerName: String?
    var command: [String]
    var kubeconfigPath: String?
    var terminalApp: ExternalTerminalApp
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
        try await runner.run(command: Self.shellCommand(for: request), terminalApp: request.terminalApp)
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
    nonisolated func run(command: String, terminalApp: ExternalTerminalApp) async throws
}

struct AppleScriptTerminalCommandRunner: TerminalCommandRunning {
    nonisolated func run(command: String, terminalApp: ExternalTerminalApp) async throws {
        switch terminalApp {
        case .terminal:
            try await runAppleScript(arguments: terminalAppleScriptArguments(command: command))
        case .iTerm2:
            try await runAppleScript(arguments: iTermAppleScriptArguments(command: command))
        case .ghostty, .warp:
            try await openCommandFile(command: command, terminalApp: terminalApp)
        }
    }

    private nonisolated func runAppleScript(arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = arguments

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

    private nonisolated func openCommandFile(command: String, terminalApp: ExternalTerminalApp) async throws {
        let fileURL = try commandFileURL(terminalApp: terminalApp)
        let script = """
        #!/bin/zsh
        \(command)
        status=$?
        printf '\\n[Vibekube] exec ended with status %s. Press Return to close this window.\\n' "$status"
        read -r _
        exit "$status"
        """

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try script.write(to: fileURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw KubernetesExecLaunchError.startFailed("Could not prepare launch script: \(error.localizedDescription)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", terminalApp.appName, fileURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = Pipe()
        let stderr = Pipe()
        process.standardError = stderr

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
                message.isEmpty ? "open exited with code \(status)" : message
            )
        }
    }

    private nonisolated func terminalAppleScriptArguments(command: String) -> [String] {
        [
            "-e",
            "tell application id \"com.apple.Terminal\" to activate",
            "-e",
            "tell application id \"com.apple.Terminal\" to do script \(appleScriptStringLiteral(command))"
        ]
    }

    private nonisolated func iTermAppleScriptArguments(command: String) -> [String] {
        [
            "-e",
            "tell application id \"com.googlecode.iterm2\"",
            "-e",
            "activate",
            "-e",
            "set newWindow to (create window with default profile)",
            "-e",
            "tell current session of newWindow to write text \(appleScriptStringLiteral(command))",
            "-e",
            "end tell"
        ]
    }

    private nonisolated func commandFileURL(terminalApp: ExternalTerminalApp) throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL
            .appendingPathComponent("Vibekube", isDirectory: true)
            .appendingPathComponent("ExecLaunches", isDirectory: true)
            .appendingPathComponent("vibekube-exec-\(terminalApp.rawValue)-\(UUID().uuidString).command")
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
