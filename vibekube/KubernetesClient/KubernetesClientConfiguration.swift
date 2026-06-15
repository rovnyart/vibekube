import Foundation

struct KubernetesClientConfiguration: Equatable {
    enum Credential: Equatable {
        case none
        case bearerToken(String)
        case clientCertificate(certificateData: Data, keyData: Data)
    }

    var contextName: String
    var namespace: String
    var serverURL: URL
    var certificateAuthorityData: Data?
    var insecureSkipTLSVerify: Bool
    var credential: Credential

    init(contextName: String, kubeconfig: Kubeconfig) throws {
        let clustersByName = Dictionary(uniqueKeysWithValues: kubeconfig.clusters.map { ($0.name, $0) })
        let usersByName = Dictionary(uniqueKeysWithValues: kubeconfig.users.map { ($0.name, $0) })

        guard let namedContext = kubeconfig.contexts.first(where: { $0.name == contextName }) else {
            throw KubernetesClientError.invalidConfiguration("Context '\(contextName)' was not found.")
        }

        guard let clusterName = namedContext.context.cluster,
              let namedCluster = clustersByName[clusterName] else {
            throw KubernetesClientError.invalidConfiguration("Context '\(contextName)' does not reference a known cluster.")
        }

        guard let server = namedCluster.cluster.server,
              let serverURL = URL(string: server),
              serverURL.scheme != nil,
              serverURL.host != nil else {
            throw KubernetesClientError.invalidConfiguration("Cluster '\(clusterName)' has an invalid server URL.")
        }

        self.contextName = contextName
        self.namespace = namedContext.context.namespace ?? "default"
        self.serverURL = serverURL
        self.certificateAuthorityData = try Self.data(
            inlineData: namedCluster.cluster.certificateAuthorityData,
            path: namedCluster.cluster.certificateAuthorityPath,
            source: namedCluster.source,
            fieldName: "certificate-authority"
        )
        self.insecureSkipTLSVerify = namedCluster.cluster.insecureSkipTLSVerify

        if let userName = namedContext.context.user,
           let namedUser = usersByName[userName] {
            self.credential = try Self.credential(from: namedUser)
        } else {
            self.credential = .none
        }
    }

    func url(path: String) -> URL {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path ?? ""
        let normalizedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        components?.path = normalizedBase + normalizedPath
        return components?.url ?? serverURL.appendingPathComponent(path)
    }

    private static func credential(from namedUser: KubeconfigNamedUser) throws -> Credential {
        switch namedUser.user.authMethod {
        case .none:
            return .none
        case .token(let token):
            return .bearerToken(token)
        case .clientCertificate(let clientCertificate):
            guard let certificateData = try data(
                inlineData: clientCertificate.clientCertificateData,
                path: clientCertificate.clientCertificatePath,
                source: namedUser.source,
                fieldName: "client-certificate"
            ) else {
                throw KubernetesClientError.invalidConfiguration("Client certificate data is missing for user '\(namedUser.name)'.")
            }

            guard let keyData = try data(
                inlineData: clientCertificate.clientKeyData,
                path: clientCertificate.clientKeyPath,
                source: namedUser.source,
                fieldName: "client-key"
            ) else {
                throw KubernetesClientError.invalidConfiguration("Client key data is missing for user '\(namedUser.name)'.")
            }

            return .clientCertificate(certificateData: certificateData, keyData: keyData)
        case .exec(let exec):
            let command = exec.commandDisplayName ?? exec.command ?? "exec plugin"
            throw KubernetesClientError.unsupportedAuthentication("Exec credential plugins are parsed, but running '\(command)' is scheduled for the next Phase 2 slice.")
        case .authProvider(let name):
            throw KubernetesClientError.unsupportedAuthentication("Legacy auth-provider '\(name)' is not implemented yet.")
        case .basicAuth:
            throw KubernetesClientError.unsupportedAuthentication("Basic auth is deprecated and not implemented yet.")
        case .unsupported(let reason):
            throw KubernetesClientError.unsupportedAuthentication(reason)
        }
    }

    private static func data(
        inlineData: Data?,
        path: String?,
        source: KubeconfigSource,
        fieldName: String
    ) throws -> Data? {
        if let inlineData {
            return inlineData
        }

        guard let path, !path.isEmpty else {
            return nil
        }

        do {
            return try Data(contentsOf: source.resolve(path: path))
        } catch {
            throw KubernetesClientError.invalidConfiguration("Could not read \(fieldName) at \(source.resolve(path: path).path).")
        }
    }
}
