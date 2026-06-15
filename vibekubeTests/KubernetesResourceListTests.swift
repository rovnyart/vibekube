import Foundation
import Testing
@testable import vibekube

@MainActor
struct KubernetesResourceListTests {

    @Test func buildsNamespacedCoreResourceListPath() {
        let pods = KubernetesDiscoveredResource(
            groupVersion: "v1",
            resource: KubernetesAPIResource(
                name: "pods",
                singularName: "",
                namespaced: true,
                kind: "Pod",
                verbs: ["list"],
                shortNames: nil,
                categories: nil
            )
        )

        #expect(pods.listPath(namespace: "vibekube-demo") == "/api/v1/namespaces/vibekube-demo/pods")
        #expect(pods.listPath(namespace: nil) == "/api/v1/pods")
        #expect(pods.itemPath(namespace: "vibekube-demo", name: "web-0") == "/api/v1/namespaces/vibekube-demo/pods/web-0")
    }

    @Test func buildsGroupedClusterScopedResourceListPath() {
        let storageClasses = KubernetesDiscoveredResource(
            groupVersion: "storage.k8s.io/v1",
            resource: KubernetesAPIResource(
                name: "storageclasses",
                singularName: "",
                namespaced: false,
                kind: "StorageClass",
                verbs: ["list"],
                shortNames: nil,
                categories: nil
            )
        )

        #expect(storageClasses.listPath(namespace: "ignored") == "/apis/storage.k8s.io/v1/storageclasses")
        #expect(storageClasses.itemPath(namespace: "ignored", name: "fast") == "/apis/storage.k8s.io/v1/storageclasses/fast")
    }

    @Test func decodesResourceListMetadataAndRows() throws {
        let list = try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "apiVersion": "v1",
                  "kind": "PodList",
                  "metadata": {
                    "resourceVersion": "123",
                    "continue": "next"
                  },
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "web-0",
                        "namespace": "vibekube-demo",
                        "uid": "pod-uid",
                        "creationTimestamp": "2026-06-15T10:00:00Z",
                        "labels": {
                          "app": "web"
                        }
                      },
                      "status": {
                        "phase": "Running"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )

        let pod = try #require(list.items.first)
        #expect(list.metadata?.resourceVersion == "123")
        #expect(list.metadata?.continueToken == "next")
        #expect(pod.displayName == "web-0")
        #expect(pod.displayNamespace == "vibekube-demo")
        #expect(pod.displayStatus == "Running")
        #expect(pod.labelsSummary == "app=web")
    }

    @Test func decodesSecretRowsWithoutReadingSecretData() throws {
        let list = try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Secret",
                      "metadata": {
                        "name": "db-password",
                        "namespace": "vibekube-demo"
                      },
                      "type": "Opaque",
                      "data": {
                        "password": "c2VjcmV0"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )

        let secret = try #require(list.items.first)
        #expect(secret.displayName == "db-password")
        #expect(secret.displayStatus == "Opaque")
        #expect(!secret.searchBlob.contains("c2VjcmV0"))
    }

    @Test func summarizesDeploymentReadiness() throws {
        let list = try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "apiVersion": "apps/v1",
                      "kind": "Deployment",
                      "metadata": {
                        "name": "api",
                        "namespace": "vibekube-demo"
                      },
                      "spec": {
                        "replicas": 3
                      },
                      "status": {
                        "readyReplicas": 2
                      }
                    }
                  ]
                }
                """.utf8
            )
        )

        #expect(list.items.first?.displayStatus == "2/3 ready")
    }

    @Test func rendersResourceDetailYAML() throws {
        let detail = try JSONDecoder().decode(
            KubernetesResourceDetail.self,
            from: Data(
                """
                {
                  "apiVersion": "v1",
                  "kind": "Pod",
                  "metadata": {
                    "name": "web-0",
                    "namespace": "vibekube-demo",
                    "labels": {
                      "app": "web"
                    }
                  },
                  "spec": {
                    "containers": [
                      {
                        "name": "web",
                        "image": "nginx:1.27",
                        "ports": [
                          {
                            "containerPort": 8080
                          }
                        ]
                      }
                    ]
                  },
                  "status": {
                    "phase": "Running"
                  }
                }
                """.utf8
            )
        )

        #expect(detail.yaml.contains("apiVersion: v1"))
        #expect(detail.yaml.contains("kind: Pod"))
        #expect(detail.yaml.contains("name: web-0"))
        #expect(detail.yaml.contains("namespace: vibekube-demo"))
        #expect(detail.yaml.contains("containers:"))
        #expect(detail.yaml.contains("image: nginx:1.27"))
        #expect(detail.yaml.contains("containerPort: 8080"))
        #expect(detail.yaml.contains("phase: Running"))
    }

    @Test func redactsSecretDetailYAML() throws {
        let detail = try JSONDecoder().decode(
            KubernetesResourceDetail.self,
            from: Data(
                """
                {
                  "apiVersion": "v1",
                  "kind": "Secret",
                  "metadata": {
                    "name": "db-password",
                    "namespace": "vibekube-demo"
                  },
                  "data": {
                    "password": "c2VjcmV0"
                  },
                  "stringData": {
                    "token": "plain-token"
                  },
                  "type": "Opaque"
                }
                """.utf8
            )
        )

        #expect(detail.yaml.contains("kind: Secret"))
        #expect(detail.yaml.contains("data: <redacted>"))
        #expect(detail.yaml.contains("stringData: <redacted>"))
        #expect(!detail.yaml.contains("c2VjcmV0"))
        #expect(!detail.yaml.contains("plain-token"))
    }

    @Test func indexesManifestSearchMatchesAcrossLines() {
        let yaml = """
        apiVersion: v1
        kind: Pod
        metadata:
          name: web-0
          namespace: vibekube-demo
        spec:
          containers:
          - name: web
            image: nginx:1.27
        """

        let matches = ManifestSearchIndex.matches(in: yaml, query: "web")

        #expect(matches.map(\.lineNumber) == [4, 8])
        #expect(matches.map(\.ordinal) == [1, 2])
    }

    @Test func manifestSearchIgnoresEmptyAndWhitespaceQueries() {
        let yaml = """
        kind: Service
        metadata:
          name: web
        """

        #expect(ManifestSearchIndex.matches(in: yaml, query: "").isEmpty)
        #expect(ManifestSearchIndex.matches(in: yaml, query: "   ").isEmpty)
    }
}
