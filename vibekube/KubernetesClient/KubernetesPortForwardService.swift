import Foundation

struct KubernetesPortForwardRequest: Equatable, Sendable {
    var contextName: String
    var namespace: String?
    var resourceKind: String
    var resourceName: String
    var localPort: Int
    var remotePort: Int
    var kubeconfigPath: String?
}

struct KubernetesPortForwardTermination: Equatable, Sendable {
    var exitCode: Int32
    var userStopped: Bool
    var message: String?
}

protocol KubernetesPortForwardHandle: AnyObject {
    var processIdentifier: Int32? { get }
    func stop()
}

protocol KubernetesPortForwardServicing {
    func startPortForward(
        request: KubernetesPortForwardRequest,
        onTermination: @escaping @Sendable (KubernetesPortForwardTermination) -> Void
    ) async throws -> KubernetesPortForwardHandle
}

struct KubectlPortForwardService: KubernetesPortForwardServicing {
    private let executableURL: URL
    private let baseEnvironment: [String: String]

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executableURL = executableURL
        self.baseEnvironment = baseEnvironment
    }

    func startPortForward(
        request: KubernetesPortForwardRequest,
        onTermination: @escaping @Sendable (KubernetesPortForwardTermination) -> Void
    ) async throws -> KubernetesPortForwardHandle {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = Self.arguments(for: request)
        process.environment = Self.environment(for: request, baseEnvironment: baseEnvironment)
        process.standardInput = FileHandle.nullDevice

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let handle = KubectlPortForwardHandle(
            process: process,
            stdout: stdout,
            stderr: stderr,
            onTermination: onTermination
        )

        do {
            try process.run()
        } catch {
            throw KubernetesPortForwardError.startFailed(error.localizedDescription)
        }

        return handle
    }

    static func arguments(for request: KubernetesPortForwardRequest) -> [String] {
        var arguments = [
            "kubectl",
            "--context",
            request.contextName
        ]

        if let namespace = request.namespace, !namespace.isEmpty {
            arguments += ["-n", namespace]
        }

        arguments += [
            "port-forward",
            "\(request.resourceKind)/\(request.resourceName)",
            "\(request.localPort):\(request.remotePort)"
        ]

        return arguments
    }

    static func environment(
        for request: KubernetesPortForwardRequest,
        baseEnvironment: [String: String]
    ) -> [String: String] {
        var environment = baseEnvironment
        environment["PATH"] = augmentedPath(baseEnvironment["PATH"])
        if let kubeconfigPath = request.kubeconfigPath, !kubeconfigPath.isEmpty {
            environment["KUBECONFIG"] = kubeconfigPath
        }
        return environment
    }

    private static func augmentedPath(_ path: String?) -> String {
        let commonExecutableDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let existingDirectories = path?
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init) ?? []
        var seen: Set<String> = []
        return (existingDirectories + commonExecutableDirectories)
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
    }
}

enum KubernetesPortForwardError: Error, LocalizedError, Equatable {
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .startFailed(let message):
            "kubectl port-forward could not be started: \(message)"
        }
    }
}

private final class KubectlPortForwardHandle: KubernetesPortForwardHandle {
    private let process: Process
    private let stdout: Pipe
    private let stderr: Pipe
    private let lock = NSLock()
    private var requestedStop = false
    private var outputData = Data()
    private var errorData = Data()

    init(
        process: Process,
        stdout: Pipe,
        stderr: Pipe,
        onTermination: @escaping @Sendable (KubernetesPortForwardTermination) -> Void
    ) {
        self.process = process
        self.stdout = stdout
        self.stderr = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.appendOutput(handle.availableData, isError: false)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.appendOutput(handle.availableData, isError: true)
        }

        process.terminationHandler = { [weak self] process in
            let userStopped = self?.didRequestStop ?? false
            let message = self?.diagnosticMessage
            self?.stdout.fileHandleForReading.readabilityHandler = nil
            self?.stderr.fileHandleForReading.readabilityHandler = nil
            onTermination(
                KubernetesPortForwardTermination(
                    exitCode: process.terminationStatus,
                    userStopped: userStopped,
                    message: message
                )
            )
        }
    }

    var processIdentifier: Int32? {
        process.processIdentifier
    }

    func stop() {
        lock.lock()
        requestedStop = true
        lock.unlock()

        if process.isRunning {
            process.terminate()
        }
    }

    private var didRequestStop: Bool {
        lock.lock()
        defer { lock.unlock() }
        return requestedStop
    }

    private var diagnosticMessage: String? {
        lock.lock()
        let data = errorData.isEmpty ? outputData : errorData
        lock.unlock()

        let message = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .suffix(3)
            .joined(separator: " ")

        return message.isEmpty ? nil : message
    }

    private func appendOutput(_ data: Data, isError: Bool) {
        guard !data.isEmpty else {
            return
        }

        lock.lock()
        if isError {
            errorData.append(data)
        } else {
            outputData.append(data)
        }
        lock.unlock()
    }
}
