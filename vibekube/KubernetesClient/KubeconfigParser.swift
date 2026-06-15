import Foundation

enum KubeconfigParserError: LocalizedError, Equatable {
    case malformedYAML(String)
    case invalidStructure(String)
    case invalidBase64(field: String, name: String)

    var errorDescription: String? {
        switch self {
        case .malformedYAML(let message):
            "Malformed YAML: \(message)"
        case .invalidStructure(let message):
            "Invalid kubeconfig: \(message)"
        case .invalidBase64(let field, let name):
            "Invalid base64 in \(field) for \(name)"
        }
    }
}

struct KubeconfigParser {
    var source: KubeconfigSource

    func parse(_ rawYAML: String) throws -> Kubeconfig {
        var yamlParser = SimpleYAMLParser()
        let root = try yamlParser.parse(rawYAML)
        guard let mapping = root.mapping else {
            throw KubeconfigParserError.invalidStructure("root document must be a mapping")
        }

        return Kubeconfig(
            apiVersion: mapping["apiVersion"]?.string,
            kind: mapping["kind"]?.string,
            clusters: try parseClusters(mapping["clusters"]?.sequence ?? []),
            contexts: parseContexts(mapping["contexts"]?.sequence ?? []),
            users: try parseUsers(mapping["users"]?.sequence ?? []),
            currentContext: mapping["current-context"]?.string
        )
    }

    private func parseClusters(_ values: [SimpleYAMLValue]) throws -> [KubeconfigNamedCluster] {
        try values.compactMap { value in
            guard let item = value.mapping,
                  let name = item["name"]?.string,
                  let cluster = item["cluster"]?.mapping else {
                return nil
            }

            return KubeconfigNamedCluster(
                name: name,
                cluster: KubeconfigCluster(
                    server: cluster["server"]?.string,
                    certificateAuthorityData: try decodeBase64(cluster["certificate-authority-data"]?.string, field: "certificate-authority-data", name: name),
                    certificateAuthorityPath: cluster["certificate-authority"]?.string,
                    insecureSkipTLSVerify: cluster["insecure-skip-tls-verify"]?.bool ?? false
                ),
                source: source
            )
        }
    }

    private func parseContexts(_ values: [SimpleYAMLValue]) -> [KubeconfigNamedContext] {
        values.compactMap { value in
            guard let item = value.mapping,
                  let name = item["name"]?.string,
                  let context = item["context"]?.mapping else {
                return nil
            }

            return KubeconfigNamedContext(
                name: name,
                context: KubeconfigContext(
                    cluster: context["cluster"]?.string,
                    user: context["user"]?.string,
                    namespace: context["namespace"]?.string
                ),
                source: source
            )
        }
    }

    private func parseUsers(_ values: [SimpleYAMLValue]) throws -> [KubeconfigNamedUser] {
        try values.compactMap { value in
            guard let item = value.mapping,
                  let name = item["name"]?.string else {
                return nil
            }

            let user = item["user"]?.mapping ?? [:]
            return KubeconfigNamedUser(
                name: name,
                user: KubeconfigUser(authMethod: try authMethod(from: user, name: name)),
                source: source
            )
        }
    }

    private func authMethod(from user: [String: SimpleYAMLValue], name: String) throws -> KubeAuthMethod {
        if let token = user["token"]?.string, !token.isEmpty {
            return .token(token)
        }

        if hasClientCertificateAuth(user) {
            return .clientCertificate(
                KubeClientCertificateAuth(
                    clientCertificateData: try decodeBase64(user["client-certificate-data"]?.string, field: "client-certificate-data", name: name),
                    clientCertificatePath: user["client-certificate"]?.string,
                    clientKeyData: try decodeBase64(user["client-key-data"]?.string, field: "client-key-data", name: name),
                    clientKeyPath: user["client-key"]?.string
                )
            )
        }

        if let exec = user["exec"]?.mapping {
            return .exec(
                KubeExecAuth(
                    apiVersion: exec["apiVersion"]?.string,
                    command: exec["command"]?.string,
                    args: exec["args"]?.sequence?.compactMap(\.string) ?? []
                )
            )
        }

        if let provider = user["auth-provider"]?.mapping {
            return .authProvider(name: provider["name"]?.string ?? "unknown")
        }

        if let username = user["username"]?.string {
            return .basicAuth(username: username)
        }

        if user.isEmpty {
            return .none
        }

        return .unsupported("Unsupported auth")
    }

    private func hasClientCertificateAuth(_ user: [String: SimpleYAMLValue]) -> Bool {
        user["client-certificate-data"] != nil ||
            user["client-certificate"] != nil ||
            user["client-key-data"] != nil ||
            user["client-key"] != nil
    }

    private func decodeBase64(_ value: String?, field: String, name: String) throws -> Data? {
        guard let value, !value.isEmpty else { return nil }
        guard let data = Data(base64Encoded: value, options: .ignoreUnknownCharacters) else {
            throw KubeconfigParserError.invalidBase64(field: field, name: name)
        }
        return data
    }
}
