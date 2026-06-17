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

    private static func environment(
        for request: KubernetesPortForwardRequest,
        baseEnvironment: [String: String]
    ) -> [String: String] {
        var environment = baseEnvironment
        if let kubeconfigPath = request.kubeconfigPath, !kubeconfigPath.isEmpty {
            environment["KUBECONFIG"] = kubeconfigPath
        }
        return environment
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

    init(
        process: Process,
        stdout: Pipe,
        stderr: Pipe,
        onTermination: @escaping @Sendable (KubernetesPortForwardTermination) -> Void
    ) {
        self.process = process
        self.stdout = stdout
        self.stderr = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        process.terminationHandler = { [weak self] process in
            let userStopped = self?.didRequestStop ?? false
            self?.stdout.fileHandleForReading.readabilityHandler = nil
            self?.stderr.fileHandleForReading.readabilityHandler = nil
            onTermination(
                KubernetesPortForwardTermination(
                    exitCode: process.terminationStatus,
                    userStopped: userStopped
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
}
