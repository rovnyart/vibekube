import Foundation
import Testing
@testable import vibekube

struct KubeconfigParserTests {

    @Test func parsesKindStyleClientCertificateConfig() throws {
        let config = try parser().parse(
            """
            apiVersion: v1
            kind: Config
            current-context: kind-vibekube-dev
            clusters:
            - name: kind-vibekube-dev
              cluster:
                certificate-authority-data: Y2E=
                server: https://127.0.0.1:6443
            contexts:
            - name: kind-vibekube-dev
              context:
                cluster: kind-vibekube-dev
                namespace: vibekube-demo
                user: kind-vibekube-dev
            users:
            - name: kind-vibekube-dev
              user:
                client-certificate-data: Y2VydA==
                client-key-data: a2V5
            """
        )

        #expect(config.currentContext == "kind-vibekube-dev")
        #expect(config.clusters.first?.cluster.server == "https://127.0.0.1:6443")
        #expect(config.clusters.first?.cluster.certificateAuthorityData == Data("ca".utf8))

        let summary = try #require(config.clusterSummaries().first)
        #expect(summary.contextName == "kind-vibekube-dev")
        #expect(summary.namespace == "vibekube-demo")
        #expect(summary.isCurrentContext)
        #expect(summary.authDescription == "Client certificate")
        #expect(summary.connectionState == .disconnected)
    }

    @Test func parsesTokenAuthAndRedactsDescription() throws {
        let config = try parser().parse(
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

        let user = try #require(config.users.first)
        #expect(user.user.authMethod.displayName == "Bearer token")
        #expect(!String(describing: user.user.authMethod).contains("super-secret-token"))
        #expect(config.clusterSummaries().first?.connectionState == .disconnected)
    }

    @Test func parsesExecAuthAsSupportedCredentialPlugin() throws {
        let config = try parser().parse(
            """
            clusters:
            - name: staging
              cluster:
                server: https://staging.example.com
            contexts:
            - name: staging
              context:
                cluster: staging
                user: staging-user
            users:
            - name: staging-user
              user:
                exec:
                  apiVersion: client.authentication.k8s.io/v1beta1
                  command: aws
                  args:
                  - eks
                  - get-token
                  - --cluster-name
                  - staging
            """
        )

        let user = try #require(config.users.first)
        guard case .exec(let exec) = user.user.authMethod else {
            Issue.record("Expected exec auth")
            return
        }

        #expect(exec.command == "aws")
        #expect(exec.args == ["eks", "get-token", "--cluster-name", "staging"])
        #expect(config.clusterSummaries().first?.authDescription == "Exec auth: aws")
        #expect(config.clusterSummaries().first?.connectionState == .disconnected)
    }

    @Test func parsesTeleportExecAuthMetadata() throws {
        let config = try parser().parse(
            """
            clusters:
            - name: corporate
              cluster:
                server: https://teleport.example.com:443
            contexts:
            - name: teleport.example.com-corporate
              context:
                cluster: corporate
                user: teleport-user
            users:
            - name: teleport-user
              user:
                exec:
                  apiVersion: client.authentication.k8s.io/v1
                  command: /opt/homebrew/bin/tsh
                  args:
                  - kube
                  - credentials
                  - --kube-cluster=corporate
                  env:
                  - name: TELEPORT_HOME
                    value: /Users/art/.tsh
                  installHint: brew install teleport
                  provideClusterInfo: true
                  interactiveMode: IfAvailable
            """
        )

        let user = try #require(config.users.first)
        guard case .exec(let exec) = user.user.authMethod else {
            Issue.record("Expected exec auth")
            return
        }

        #expect(exec.isTeleport)
        #expect(exec.commandDisplayName == "tsh")
        #expect(exec.env == [KubeExecEnvironmentVariable(name: "TELEPORT_HOME", value: "/Users/art/.tsh")])
        #expect(exec.installHint == "brew install teleport")
        #expect(exec.provideClusterInfo)
        #expect(exec.interactiveMode == "IfAvailable")
        #expect(config.clusterSummaries().first?.authDescription == "Teleport exec auth (tsh)")
        #expect(config.clusterSummaries().first?.connectionState == .disconnected)
    }

    @Test func rejectsMalformedYAML() throws {
        #expect(throws: KubeconfigParserError.self) {
            try parser().parse(
                """
                apiVersion: v1
                  kind: Config
                """
            )
        }
    }

    @Test func loaderMergesKubeconfigPathListWithFirstFileWinning() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let first = directory.appendingPathComponent("first.yaml")
        let second = directory.appendingPathComponent("second.yaml")
        try """
        current-context: first
        clusters:
        - name: shared
          cluster:
            server: https://first.example.com
        contexts:
        - name: first
          context:
            cluster: shared
            user: first-user
        users:
        - name: first-user
          user:
            token: first-token
        """.write(to: first, atomically: true, encoding: .utf8)

        try """
        current-context: second
        clusters:
        - name: shared
          cluster:
            server: https://second.example.com
        contexts:
        - name: second
          context:
            cluster: shared
            user: second-user
        users:
        - name: second-user
          user:
            token: second-token
        """.write(to: second, atomically: true, encoding: .utf8)

        let loader = KubeconfigLoader(environment: ["KUBECONFIG": "\(first.path):\(second.path)"])
        let result = loader.load()

        #expect(result.issues.isEmpty)
        #expect(result.kubeconfig.currentContext == "first")
        #expect(result.kubeconfig.clusters.first?.cluster.server == "https://first.example.com")
        #expect(result.kubeconfig.contexts.map(\.name) == ["first", "second"])
    }

    @Test func loaderUsesPathOverrideBeforeEnvironmentKubeconfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let environmentConfig = directory.appendingPathComponent("environment.yaml")
        let overrideConfig = directory.appendingPathComponent("override.yaml")
        try kubeconfig(named: "environment", server: "https://environment.example.com")
            .write(to: environmentConfig, atomically: true, encoding: .utf8)
        try kubeconfig(named: "override", server: "https://override.example.com")
            .write(to: overrideConfig, atomically: true, encoding: .utf8)

        let loader = KubeconfigLoader(
            environment: ["KUBECONFIG": environmentConfig.path],
            pathOverride: overrideConfig.path
        )
        let result = loader.load()

        #expect(result.issues.isEmpty)
        #expect(result.requestedPaths.map(\.url.path) == [overrideConfig.path])
        #expect(result.kubeconfig.currentContext == "override")
        #expect(result.kubeconfig.clusters.first?.cluster.server == "https://override.example.com")
    }

    private func parser() -> KubeconfigParser {
        KubeconfigParser(source: KubeconfigSource(url: URL(fileURLWithPath: "/tmp/kubeconfig")))
    }

    private func kubeconfig(named name: String, server: String) -> String {
        """
        current-context: \(name)
        clusters:
        - name: \(name)
          cluster:
            server: \(server)
        contexts:
        - name: \(name)
          context:
            cluster: \(name)
            user: \(name)-user
        users:
        - name: \(name)-user
          user:
            token: \(name)-token
        """
    }
}
