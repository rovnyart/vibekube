import Foundation
import Testing
@testable import vibekube

struct KubernetesExecCredentialTests {

    @Test func decodesBearerTokenExecCredential() throws {
        let credential = try JSONDecoder.kubernetesExecCredential.decode(
            KubernetesExecCredential.self,
            from: Data(
                """
                {
                  "apiVersion": "client.authentication.k8s.io/v1",
                  "kind": "ExecCredential",
                  "status": {
                    "expirationTimestamp": "2030-01-02T03:04:05Z",
                    "token": "secret-token"
                  }
                }
                """.utf8
            )
        )

        let resolved = try credential.resolvedCredential(commandDisplayName: "tsh")

        guard case .bearerToken(let token) = resolved.credential else {
            Issue.record("Expected bearer token")
            return
        }

        #expect(token == "secret-token")
        #expect(resolved.expirationTimestamp != nil)
    }

    @Test func decodesClientCertificateExecCredentialAsPEMData() throws {
        let certificatePEM = """
        -----BEGIN CERTIFICATE-----
        abc
        -----END CERTIFICATE-----
        """
        let keyPEM = """
        -----BEGIN PRIVATE KEY-----
        def
        -----END PRIVATE KEY-----
        """
        let json = """
        {
          "apiVersion": "client.authentication.k8s.io/v1beta1",
          "kind": "ExecCredential",
          "status": {
            "clientCertificateData": "\(certificatePEM.escapedForJSONString)",
            "clientKeyData": "\(keyPEM.escapedForJSONString)"
          }
        }
        """

        let credential = try JSONDecoder.kubernetesExecCredential.decode(
            KubernetesExecCredential.self,
            from: Data(json.utf8)
        )
        let resolved = try credential.resolvedCredential(commandDisplayName: "aws")

        guard case .clientCertificate(let certificateData, let keyData) = resolved.credential else {
            Issue.record("Expected client certificate")
            return
        }

        #expect(certificateData == Data(certificatePEM.utf8))
        #expect(keyData == Data(keyPEM.utf8))
    }

    @Test func encodesKubernetesExecInfoWhenClusterInfoIsRequested() throws {
        let request = KubernetesExecCredentialRequest(
            contextName: "teleport",
            clusterName: "corporate",
            userName: "teleport-user",
            exec: KubeExecAuth(
                apiVersion: "client.authentication.k8s.io/v1",
                command: "tsh",
                args: [],
                env: [],
                installHint: nil,
                provideClusterInfo: true,
                interactiveMode: "IfAvailable"
            ),
            cluster: KubernetesExecClusterInfo(
                server: "https://teleport.example.com",
                certificateAuthorityData: Data("ca".utf8),
                insecureSkipTLSVerify: false
            )
        )

        let json = try #require(request.execInfoJSON)

        #expect(json.contains("\"kind\":\"ExecCredential\""))
        #expect(json.contains("\"interactive\":true"))
        #expect(json.contains("\"server\":\"https:\\/\\/teleport.example.com\"") || json.contains("\"server\":\"https://teleport.example.com\""))
        #expect(json.contains("\"certificate-authority-data\":\"Y2E=\""))
    }

    @Test func providerCachesCredentialsUntilExpiry() async throws {
        let runner = StubExecCredentialRunner(
            credentials: [
                try execCredentialJSON(token: "first", expirationTimestamp: "2030-01-01T00:00:00Z"),
                try execCredentialJSON(token: "second", expirationTimestamp: "2030-01-01T00:00:00Z")
            ]
        )
        let provider = DefaultKubernetesExecCredentialProvider(runner: runner)
        let request = execRequest()

        let first = try await provider.credential(for: request)
        let second = try await provider.credential(for: request)

        guard case .bearerToken(let firstToken) = first,
              case .bearerToken(let secondToken) = second else {
            Issue.record("Expected bearer tokens")
            return
        }

        #expect(firstToken == "first")
        #expect(secondToken == "first")
        #expect(runner.runCount == 1)
    }

    @Test func providerRerunsExpiredCredentials() async throws {
        let runner = StubExecCredentialRunner(
            credentials: [
                try execCredentialJSON(token: "expired", expirationTimestamp: "2000-01-01T00:00:00Z"),
                try execCredentialJSON(token: "fresh", expirationTimestamp: "2030-01-01T00:00:00Z")
            ]
        )
        let provider = DefaultKubernetesExecCredentialProvider(runner: runner)
        let request = execRequest()

        _ = try await provider.credential(for: request)
        let fresh = try await provider.credential(for: request)

        guard case .bearerToken(let token) = fresh else {
            Issue.record("Expected bearer token")
            return
        }

        #expect(token == "fresh")
        #expect(runner.runCount == 2)
    }

    @Test func defaultRunnerExecutesCommandAndDecodesCredential() async throws {
        let json = Self.execCredentialJSONString(token: "from-process", expirationTimestamp: "2030-01-01T00:00:00Z")
        let request = KubernetesExecCredentialRequest(
            contextName: "demo",
            clusterName: "demo",
            userName: "demo-user",
            exec: KubeExecAuth(
                apiVersion: "client.authentication.k8s.io/v1",
                command: "/usr/bin/printf",
                args: [json],
                env: [],
                installHint: nil,
                provideClusterInfo: false,
                interactiveMode: "Never"
            ),
            cluster: KubernetesExecClusterInfo(
                server: "https://demo.example.com",
                certificateAuthorityData: nil,
                insecureSkipTLSVerify: false
            )
        )

        let credential = try await DefaultKubernetesExecCredentialRunner().run(request: request)
        let resolved = try credential.resolvedCredential(commandDisplayName: "printf")

        guard case .bearerToken(let token) = resolved.credential else {
            Issue.record("Expected bearer token")
            return
        }

        #expect(token == "from-process")
    }

    private func execRequest() -> KubernetesExecCredentialRequest {
        KubernetesExecCredentialRequest(
            contextName: "demo",
            clusterName: "demo",
            userName: "demo-user",
            exec: KubeExecAuth(
                apiVersion: "client.authentication.k8s.io/v1",
                command: "demo-auth",
                args: [],
                env: [],
                installHint: nil,
                provideClusterInfo: false,
                interactiveMode: "Never"
            ),
            cluster: KubernetesExecClusterInfo(
                server: "https://demo.example.com",
                certificateAuthorityData: nil,
                insecureSkipTLSVerify: false
            )
        )
    }

    private func execCredentialJSON(token: String, expirationTimestamp: String) throws -> KubernetesExecCredential {
        try JSONDecoder.kubernetesExecCredential.decode(
            KubernetesExecCredential.self,
            from: Data(Self.execCredentialJSONString(token: token, expirationTimestamp: expirationTimestamp).utf8)
        )
    }

    private static func execCredentialJSONString(token: String, expirationTimestamp: String) -> String {
        """
        {"apiVersion":"client.authentication.k8s.io/v1","kind":"ExecCredential","status":{"expirationTimestamp":"\(expirationTimestamp)","token":"\(token)"}}
        """
    }
}

private final class StubExecCredentialRunner: KubernetesExecCredentialRunning {
    private var credentials: [KubernetesExecCredential]
    private(set) var runCount = 0

    init(credentials: [KubernetesExecCredential]) {
        self.credentials = credentials
    }

    func run(request: KubernetesExecCredentialRequest) async throws -> KubernetesExecCredential {
        runCount += 1
        return credentials.removeFirst()
    }
}

private extension String {
    var escapedForJSONString: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
