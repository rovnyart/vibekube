import Foundation

struct KubeconfigSource: Hashable {
    var url: URL

    var displayName: String {
        displayPath
    }

    var displayPath: String {
        let path = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == "\(home)/.kube/config" {
            return "~/.kube/config"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    func resolve(path: String) -> URL {
        let expandedPath = (path as NSString).expandingTildeInPath
        if (expandedPath as NSString).isAbsolutePath {
            return URL(fileURLWithPath: expandedPath).standardizedFileURL
        }

        return self.url
            .deletingLastPathComponent()
            .appendingPathComponent(expandedPath)
            .standardizedFileURL
    }
}

struct Kubeconfig: Equatable {
    var apiVersion: String?
    var kind: String?
    var clusters: [KubeconfigNamedCluster]
    var contexts: [KubeconfigNamedContext]
    var users: [KubeconfigNamedUser]
    var currentContext: String?

    static let empty = Kubeconfig(
        apiVersion: nil,
        kind: nil,
        clusters: [],
        contexts: [],
        users: [],
        currentContext: nil
    )
}

struct KubeconfigNamedCluster: Equatable {
    var name: String
    var cluster: KubeconfigCluster
    var source: KubeconfigSource
}

struct KubeconfigCluster: Equatable {
    var server: String?
    var certificateAuthorityData: Data?
    var certificateAuthorityPath: String?
    var insecureSkipTLSVerify: Bool
}

struct KubeconfigNamedContext: Equatable {
    var name: String
    var context: KubeconfigContext
    var source: KubeconfigSource
}

struct KubeconfigContext: Equatable {
    var cluster: String?
    var user: String?
    var namespace: String?
}

struct KubeconfigNamedUser: Equatable {
    var name: String
    var user: KubeconfigUser
    var source: KubeconfigSource
}

struct KubeconfigUser: Equatable {
    var authMethod: KubeAuthMethod
}

enum KubeAuthMethod: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case token(String)
    case clientCertificate(KubeClientCertificateAuth)
    case exec(KubeExecAuth)
    case authProvider(name: String)
    case basicAuth(username: String)
    case unsupported(String)

    var displayName: String {
        switch self {
        case .none:
            "No user"
        case .token:
            "Bearer token"
        case .clientCertificate:
            "Client certificate"
        case .exec(let exec):
            if exec.isTeleport {
                "Teleport exec auth (tsh)"
            } else {
                "Exec auth\(exec.commandDisplayName.map { ": \($0)" } ?? "")"
            }
        case .authProvider(let name):
            "Auth provider: \(name)"
        case .basicAuth:
            "Basic auth"
        case .unsupported(let reason):
            reason
        }
    }

    var description: String {
        displayName
    }

    var debugDescription: String {
        displayName
    }

    var isInitiallySupported: Bool {
        switch self {
        case .none, .token, .clientCertificate, .exec:
            true
        case .authProvider, .basicAuth, .unsupported:
            false
        }
    }
}

struct KubeClientCertificateAuth: Equatable {
    var clientCertificateData: Data?
    var clientCertificatePath: String?
    var clientKeyData: Data?
    var clientKeyPath: String?
}

struct KubeExecAuth: Equatable {
    var apiVersion: String?
    var command: String?
    var args: [String]
    var env: [KubeExecEnvironmentVariable]
    var installHint: String?
    var provideClusterInfo: Bool
    var interactiveMode: String?

    var commandDisplayName: String? {
        guard let command, !command.isEmpty else { return nil }
        return URL(fileURLWithPath: command).lastPathComponent
    }

    var isTeleport: Bool {
        commandDisplayName == "tsh"
    }
}

struct KubeExecEnvironmentVariable: Equatable {
    var name: String
    var value: String
}

extension Kubeconfig {
    func clusterSummaries() -> [ClusterSummary] {
        let clustersByName = Dictionary(uniqueKeysWithValues: clusters.map { ($0.name, $0) })
        let usersByName = Dictionary(uniqueKeysWithValues: users.map { ($0.name, $0) })

        return contexts.map { namedContext in
            let cluster = namedContext.context.cluster.flatMap { clustersByName[$0] }
            let user = namedContext.context.user.flatMap { usersByName[$0] }
            let authMethod = user?.user.authMethod ?? .none
            let isSupported = authMethod.isInitiallySupported

            return ClusterSummary(
                id: namedContext.name,
                name: namedContext.name,
                contextName: namedContext.name,
                server: cluster?.cluster.server ?? "Unknown server",
                namespace: namedContext.context.namespace ?? "default",
                sourceName: namedContext.source.displayName,
                isCurrentContext: namedContext.name == currentContext,
                authDescription: authMethod.displayName,
                connectionState: isSupported ? .disconnected : .unsupportedAuth,
                kubernetesVersion: nil,
                lastSeenAt: nil
            )
        }
        .sorted { lhs, rhs in
            if lhs.isCurrentContext != rhs.isCurrentContext {
                return lhs.isCurrentContext && !rhs.isCurrentContext
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
