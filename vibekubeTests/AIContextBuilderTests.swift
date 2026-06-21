import Foundation
import Testing
@testable import vibekube

struct AIContextBuilderTests {
    @Test func redactsSecretManifestDataBlocks() {
        let yaml = """
        apiVersion: v1
        kind: Secret
        metadata:
          name: demo-secret
        data:
          password: cGFzc3dvcmQ=
          token: dG9rZW4=
        stringData:
          apiKey: raw-api-key
        type: Opaque
        """

        let redacted = AIContextRedactor.redactedManifest(yaml, kind: "Secret")

        #expect(redacted.contains("data:"))
        #expect(redacted.contains("password: <redacted>"))
        #expect(redacted.contains("token: <redacted>"))
        #expect(redacted.contains("apiKey: <redacted>"))
        #expect(redacted.contains("type: Opaque"))
        #expect(!redacted.contains("cGFzc3dvcmQ="))
        #expect(!redacted.contains("dG9rZW4="))
        #expect(!redacted.contains("raw-api-key"))
    }

    @Test func redactsCredentialTextInNonSecretManifest() {
        let yaml = """
        apiVersion: v1
        kind: ConfigMap
        data:
          config: Authorization: Bearer super-secret-token
          password: hunter2
        """

        let redacted = AIContextRedactor.redactedManifest(yaml, kind: "ConfigMap")

        #expect(redacted.contains("Bearer <redacted>"))
        #expect(redacted.contains("password: <redacted>"))
        #expect(!redacted.contains("super-secret-token"))
        #expect(!redacted.contains("hunter2"))
    }

    @Test func contextIncludesRedactedBoundedLogSnippets() throws {
        let detail = try podDetailSnapshot(yamlPadding: String(repeating: "x", count: 20_000))
        let logs = PodLogSnapshot(
            query: PodLogQuery(
                contextID: "kind-demo",
                namespace: "vibekube-demo",
                podName: "echo-web",
                containerName: "app",
                previous: false,
                tailLines: 500,
                sinceSeconds: nil,
                timestamps: false,
                follow: false
            ),
            text: "ready\nAuthorization: Bearer log-secret-token\npassword=hunter2",
            loadedAt: Date()
        )

        let context = AIContextBuilder.resourceContext(
            detail: detail,
            cluster: nil,
            namespaceTitle: "vibekube-demo",
            eventState: .idle,
            logSnapshots: [logs]
        )

        let prompt = context.promptText
        #expect(prompt.contains("Selected Log Snippets"))
        #expect(prompt.contains("Bearer <redacted>"))
        #expect(prompt.contains("password=<redacted>"))
        #expect(prompt.contains("<truncated by Vibekube before AI request>"))
        #expect(!prompt.contains("log-secret-token"))
        #expect(!prompt.contains("hunter2"))
        #expect(prompt.count < 35_000)
    }

    @Test func contextIncludesRelatedResourcesAndRedactedEnvironment() throws {
        let detail = try podDetailSnapshot()

        let context = AIContextBuilder.resourceContext(
            detail: detail,
            cluster: nil,
            namespaceTitle: "vibekube-demo",
            eventState: .idle
        )
        let prompt = context.promptText

        #expect(prompt.contains("Related Resources"))
        #expect(prompt.contains("owner Deployment/echo-web"))
        #expect(prompt.contains("selector app=echo"))
        #expect(prompt.contains("Secret/demo-secret"))
        #expect(prompt.contains("Environment"))
        #expect(prompt.contains("PUBLIC_MODE=demo"))
        #expect(prompt.contains("API_TOKEN=<redacted>"))
        #expect(prompt.contains("PASSWORD=<redacted>"))
        #expect(prompt.contains("SECRET_VALUE=<from secretKeyRef demo-secret/token>"))
        #expect(!prompt.contains("literal-token"))
        #expect(!prompt.contains("hunter2"))
    }

    private func podDetailSnapshot(yamlPadding: String = "") throws -> ResourceDetailSnapshot {
        let resource = KubernetesDiscoveredResource(
            groupVersion: "v1",
            resource: KubernetesAPIResource(
                name: "pods",
                singularName: "",
                namespaced: true,
                kind: "Pod",
                verbs: ["get", "list"],
                shortNames: ["po"],
                categories: nil
            )
        )
        let yaml = """
        apiVersion: v1
        kind: Pod
        metadata:
          name: echo-web
          namespace: vibekube-demo
          annotations:
            padding: \(yamlPadding)
        status:
          phase: Running
        """
        let value = KubernetesJSONValue.object([
            "apiVersion": .string("v1"),
            "kind": .string("Pod"),
            "metadata": .object([
                "name": .string("echo-web"),
                "namespace": .string("vibekube-demo"),
                "ownerReferences": .array([
                    .object([
                        "kind": .string("Deployment"),
                        "name": .string("echo-web")
                    ])
                ])
            ]),
            "spec": .object([
                "selector": .object([
                    "matchLabels": .object([
                        "app": .string("echo")
                    ])
                ]),
                "containers": .array([
                    .object([
                        "name": .string("app"),
                        "env": .array([
                            .object([
                                "name": .string("PUBLIC_MODE"),
                                "value": .string("demo")
                            ]),
                            .object([
                                "name": .string("API_TOKEN"),
                                "value": .string("literal-token")
                            ]),
                            .object([
                                "name": .string("PASSWORD"),
                                "value": .string("hunter2")
                            ]),
                            .object([
                                "name": .string("SECRET_VALUE"),
                                "valueFrom": .object([
                                    "secretKeyRef": .object([
                                        "name": .string("demo-secret"),
                                        "key": .string("token")
                                    ])
                                ])
                            ])
                        ]),
                        "envFrom": .array([
                            .object([
                                "secretRef": .object([
                                    "name": .string("demo-secret")
                                ])
                            ])
                        ])
                    ])
                ])
            ]),
            "status": .object([
                "phase": .string("Running")
            ])
        ])
        return ResourceDetailSnapshot(
            query: ResourceDetailQuery(
                contextID: "kind-demo",
                resource: resource,
                namespace: "vibekube-demo",
                name: "echo-web"
            ),
            yaml: yaml,
            summary: KubernetesResourceDetailSummary(value: value),
            loadedAt: Date()
        )
    }
}
