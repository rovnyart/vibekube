import Foundation

struct KubernetesExecClusterInfo: Equatable {
    var server: String
    var certificateAuthorityData: Data?
    var insecureSkipTLSVerify: Bool
}

struct KubernetesExecCredentialRequest: Equatable {
    var contextName: String
    var clusterName: String
    var userName: String
    var exec: KubeExecAuth
    var cluster: KubernetesExecClusterInfo

    var commandDisplayName: String {
        exec.commandDisplayName ?? exec.command ?? "exec plugin"
    }

    var cacheKey: KubernetesExecCredentialCacheKey {
        KubernetesExecCredentialCacheKey(
            contextName: contextName,
            clusterName: clusterName,
            userName: userName,
            command: exec.command ?? "",
            args: exec.args,
            env: exec.env.map { "\($0.name)=\($0.value)" },
            server: cluster.server
        )
    }

    var execInfoJSON: String? {
        guard exec.provideClusterInfo else {
            return nil
        }

        let info = KubernetesExecInfo(
            apiVersion: exec.apiVersion ?? "client.authentication.k8s.io/v1",
            spec: KubernetesExecInfo.Spec(
                interactive: allowsInteractiveFlow,
                cluster: KubernetesExecInfo.Cluster(
                    server: cluster.server,
                    certificateAuthorityData: cluster.certificateAuthorityData?.base64EncodedString(),
                    insecureSkipTLSVerify: cluster.insecureSkipTLSVerify
                )
            )
        )

        guard let data = try? JSONEncoder().encode(info) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private var allowsInteractiveFlow: Bool {
        switch exec.interactiveMode?.lowercased() {
        case "never":
            false
        default:
            true
        }
    }
}

struct KubernetesExecCredentialCacheKey: Hashable {
    var contextName: String
    var clusterName: String
    var userName: String
    var command: String
    var args: [String]
    var env: [String]
    var server: String
}

struct KubernetesExecCredential: Decodable, Equatable {
    var apiVersion: String?
    var kind: String?
    var status: Status?

    struct Status: Decodable, Equatable {
        var expirationTimestamp: Date?
        var token: String?
        var clientCertificateData: String?
        var clientKeyData: String?
    }

    func resolvedCredential(commandDisplayName: String) throws -> ResolvedKubernetesExecCredential {
        guard let status else {
            throw KubernetesClientError.execCredential("Exec credential command '\(commandDisplayName)' returned no credential status.")
        }

        if let token = status.token, !token.isEmpty {
            return ResolvedKubernetesExecCredential(
                credential: .bearerToken(token),
                expirationTimestamp: status.expirationTimestamp
            )
        }

        if let certificateData = status.clientCertificateData,
           let keyData = status.clientKeyData,
           !certificateData.isEmpty,
           !keyData.isEmpty {
            return ResolvedKubernetesExecCredential(
                credential: .clientCertificate(
                    certificateData: Data(certificateData.utf8),
                    keyData: Data(keyData.utf8)
                ),
                expirationTimestamp: status.expirationTimestamp
            )
        }

        throw KubernetesClientError.execCredential("Exec credential command '\(commandDisplayName)' returned no usable token or client certificate.")
    }
}

struct ResolvedKubernetesExecCredential: Equatable {
    var credential: KubernetesClientConfiguration.Credential
    var expirationTimestamp: Date?
}

private struct KubernetesExecInfo: Encodable {
    var apiVersion: String
    var kind = "ExecCredential"
    var spec: Spec

    struct Spec: Encodable {
        var interactive: Bool
        var cluster: Cluster?
    }

    struct Cluster: Encodable {
        var server: String
        var certificateAuthorityData: String?
        var insecureSkipTLSVerify: Bool

        enum CodingKeys: String, CodingKey {
            case server
            case certificateAuthorityData = "certificate-authority-data"
            case insecureSkipTLSVerify = "insecure-skip-tls-verify"
        }
    }
}

extension JSONDecoder {
    static var kubernetesExecCredential: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = ISO8601DateFormatter.kubernetesInternetDateTime.date(from: value) {
                return date
            }
            if let date = ISO8601DateFormatter.kubernetesInternetDateTimeWithFractionalSeconds.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid Kubernetes timestamp."
            )
        }
        return decoder
    }
}

private extension ISO8601DateFormatter {
    static let kubernetesInternetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let kubernetesInternetDateTimeWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
