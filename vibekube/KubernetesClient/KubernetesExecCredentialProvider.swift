import Foundation

protocol KubernetesExecCredentialProviding {
    func credential(for request: KubernetesExecCredentialRequest) async throws -> KubernetesClientConfiguration.Credential
    func invalidate(_ request: KubernetesExecCredentialRequest)
}

final class DefaultKubernetesExecCredentialProvider: KubernetesExecCredentialProviding {
    private struct CachedCredential {
        var credential: KubernetesClientConfiguration.Credential
        var expirationTimestamp: Date?

        var isValid: Bool {
            guard let expirationTimestamp else {
                return true
            }
            return expirationTimestamp.timeIntervalSinceNow > 30
        }
    }

    private let runner: KubernetesExecCredentialRunning
    private var cache: [KubernetesExecCredentialCacheKey: CachedCredential] = [:]

    init(runner: KubernetesExecCredentialRunning = DefaultKubernetesExecCredentialRunner()) {
        self.runner = runner
    }

    func credential(for request: KubernetesExecCredentialRequest) async throws -> KubernetesClientConfiguration.Credential {
        let key = request.cacheKey
        if let cached = cache[key], cached.isValid {
            return cached.credential
        }

        let execCredential = try await runner.run(request: request)
        let resolved = try execCredential.resolvedCredential(commandDisplayName: request.commandDisplayName)
        cache[key] = CachedCredential(
            credential: resolved.credential,
            expirationTimestamp: resolved.expirationTimestamp
        )
        return resolved.credential
    }

    func invalidate(_ request: KubernetesExecCredentialRequest) {
        cache[request.cacheKey] = nil
    }
}

protocol KubernetesExecCredentialRunning {
    func run(request: KubernetesExecCredentialRequest) async throws -> KubernetesExecCredential
}

struct DefaultKubernetesExecCredentialRunner: KubernetesExecCredentialRunning {
    private let fileManager: FileManager
    private let baseEnvironment: [String: String]

    init(
        fileManager: FileManager = .default,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.baseEnvironment = baseEnvironment
    }

    func run(request: KubernetesExecCredentialRequest) async throws -> KubernetesExecCredential {
        guard let command = request.exec.command, !command.isEmpty else {
            throw KubernetesClientError.unsupportedAuthentication("Exec credential command is missing.")
        }

        let executableURL = try executableURL(
            for: command,
            installHint: request.exec.installHint
        )

        let process = Process()
        process.executableURL = executableURL
        process.arguments = request.exec.args
        process.environment = environment(for: request)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let termination = ProcessTermination()
        process.terminationHandler = { process in
            termination.resume(status: process.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            throw KubernetesClientError.execCredential(
                "Exec credential command '\(request.commandDisplayName)' could not be started: \(error.localizedDescription)"
            )
        }

        try Task.checkCancellation()
        let status = await withTaskCancellationHandler {
            await termination.wait()
        } onCancel: {
            process.terminate()
        }
        try Task.checkCancellation()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        let stderrMessage = Self.diagnosticMessage(from: errorOutput)

        guard status == 0 else {
            throw KubernetesClientError.execCredential(
                "Exec credential command '\(request.commandDisplayName)' failed with exit code \(status)\(stderrMessage.map { ": \($0)" } ?? ".")"
            )
        }

        do {
            return try JSONDecoder.kubernetesExecCredential.decode(KubernetesExecCredential.self, from: output)
        } catch {
            throw KubernetesClientError.execCredential(
                "Exec credential command '\(request.commandDisplayName)' did not return valid ExecCredential JSON\(stderrMessage.map { ": \($0)" } ?? ".")"
            )
        }
    }

    private static func diagnosticMessage(from data: Data) -> String? {
        let message = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !message.isEmpty else {
            return nil
        }

        let lines = message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: " ")

        return DiagnosticsRedactor.redactedText(String(lines.prefix(1_000)))
    }

    private func executableURL(for command: String, installHint: String?) throws -> URL {
        let expandedCommand = (command as NSString).expandingTildeInPath
        let commandPath = expandedCommand as NSString

        if commandPath.contains("/") {
            guard fileManager.isExecutableFile(atPath: expandedCommand) else {
                throw missingCommand(command, installHint: installHint)
            }
            return URL(fileURLWithPath: expandedCommand)
        }

        for directory in executableSearchPaths() {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(expandedCommand).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        throw missingCommand(command, installHint: installHint)
    }

    private func executableSearchPaths() -> [String] {
        let environmentPaths = (baseEnvironment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
        let macDeveloperPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]

        var seen = Set<String>()
        return (environmentPaths + macDeveloperPaths).filter { path in
            seen.insert(path).inserted
        }
    }

    private func environment(for request: KubernetesExecCredentialRequest) -> [String: String] {
        var environment = baseEnvironment
        let path = executableSearchPaths().joined(separator: ":")
        if environment["PATH"]?.isEmpty ?? true {
            environment["PATH"] = path
        } else {
            environment["PATH"] = "\(environment["PATH"] ?? ""):\(path)"
        }

        for variable in request.exec.env {
            environment[variable.name] = variable.value
        }

        if let execInfoJSON = request.execInfoJSON {
            environment["KUBERNETES_EXEC_INFO"] = execInfoJSON
        }

        return environment
    }

    private func missingCommand(_ command: String, installHint: String?) -> KubernetesClientError {
        if let installHint, !installHint.isEmpty {
            return .unsupportedAuthentication("Exec credential command '\(command)' was not found. \(installHint)")
        }
        return .unsupportedAuthentication("Exec credential command '\(command)' was not found.")
    }
}

nonisolated private final class ProcessTermination: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int32, Never>?
    private var status: Int32?

    func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let status {
                lock.unlock()
                continuation.resume(returning: status)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func resume(status: Int32) {
        lock.lock()
        guard self.status == nil else {
            lock.unlock()
            return
        }

        self.status = status
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(returning: status)
    }
}
