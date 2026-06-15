import Foundation
import Testing
@testable import vibekube

struct KubernetesClientConfigurationTests {

    @Test func buildsClientCertificateConfigurationFromInlineData() throws {
        let kubeconfig = try parser().parse(
            """
            clusters:
            - name: demo
              cluster:
                server: https://127.0.0.1:6443/base
                certificate-authority-data: Y2E=
            contexts:
            - name: demo
              context:
                cluster: demo
                namespace: vibekube-demo
                user: demo-user
            users:
            - name: demo-user
              user:
                client-certificate-data: Y2VydA==
                client-key-data: a2V5
            """
        )

        let configuration = try KubernetesClientConfiguration(contextName: "demo", kubeconfig: kubeconfig)

        #expect(configuration.contextName == "demo")
        #expect(configuration.namespace == "vibekube-demo")
        #expect(configuration.serverURL.absoluteString == "https://127.0.0.1:6443/base")
        #expect(configuration.url(path: "/version").absoluteString == "https://127.0.0.1:6443/base/version")
        #expect(configuration.certificateAuthorityData == Data("ca".utf8))

        guard case .clientCertificate(let certificateData, let keyData) = configuration.credential else {
            Issue.record("Expected client certificate credential")
            return
        }

        #expect(certificateData == Data("cert".utf8))
        #expect(keyData == Data("key".utf8))
    }

    @Test func resolvesRelativeCertificatePathsAgainstKubeconfigSource() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try Data("ca".utf8).write(to: directory.appendingPathComponent("ca.crt"))
        try Data("cert".utf8).write(to: directory.appendingPathComponent("client.crt"))
        try Data("key".utf8).write(to: directory.appendingPathComponent("client.key"))

        let source = KubeconfigSource(url: directory.appendingPathComponent("config.yaml"))
        let kubeconfig = try KubeconfigParser(source: source).parse(
            """
            clusters:
            - name: demo
              cluster:
                server: https://demo.example.com
                certificate-authority: ca.crt
            contexts:
            - name: demo
              context:
                cluster: demo
                user: demo-user
            users:
            - name: demo-user
              user:
                client-certificate: client.crt
                client-key: client.key
            """
        )

        let configuration = try KubernetesClientConfiguration(contextName: "demo", kubeconfig: kubeconfig)

        #expect(configuration.certificateAuthorityData == Data("ca".utf8))
        guard case .clientCertificate(let certificateData, let keyData) = configuration.credential else {
            Issue.record("Expected client certificate credential")
            return
        }

        #expect(certificateData == Data("cert".utf8))
        #expect(keyData == Data("key".utf8))
    }

    @Test func buildsBearerTokenConfigurationWithoutLeakingTokenInDescription() throws {
        let kubeconfig = try parser().parse(
            """
            clusters:
            - name: prod
              cluster:
                server: https://prod.example.com
            contexts:
            - name: prod
              context:
                cluster: prod
                user: prod-user
            users:
            - name: prod-user
              user:
                token: super-secret-token
            """
        )

        let configuration = try KubernetesClientConfiguration(contextName: "prod", kubeconfig: kubeconfig)

        guard case .bearerToken(let token) = configuration.credential else {
            Issue.record("Expected bearer token credential")
            return
        }

        #expect(token == "super-secret-token")
        #expect(KubeAuthMethod.token(token).displayName == "Bearer token")
    }

    @Test func buildsExecAuthConfigurationForCredentialProvider() throws {
        let kubeconfig = try parser().parse(
            """
            clusters:
            - name: corporate
              cluster:
                server: https://teleport.example.com
            contexts:
            - name: corporate
              context:
                cluster: corporate
                user: teleport-user
            users:
            - name: teleport-user
              user:
                exec:
                  command: tsh
                  args:
                  - kube
                  - credentials
            """
        )

        let configuration = try KubernetesClientConfiguration(contextName: "corporate", kubeconfig: kubeconfig)

        guard case .exec(let request) = configuration.credential else {
            Issue.record("Expected exec credential request")
            return
        }

        #expect(request.contextName == "corporate")
        #expect(request.clusterName == "corporate")
        #expect(request.userName == "teleport-user")
        #expect(request.exec.command == "tsh")
        #expect(request.cluster.server == "https://teleport.example.com")
    }

    private func parser() -> KubeconfigParser {
        KubeconfigParser(source: KubeconfigSource(url: URL(fileURLWithPath: "/tmp/kube/config.yaml")))
    }
}
