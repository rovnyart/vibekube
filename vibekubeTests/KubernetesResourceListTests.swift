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

    @Test func extractsResourceDetailSummary() throws {
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
                    "uid": "pod-uid",
                    "resourceVersion": "42",
                    "creationTimestamp": "2026-06-15T10:00:00Z",
                    "labels": {
                      "app": "web"
                    },
                    "annotations": {
                      "vibekube.io/demo": "true",
                      "kubectl.kubernetes.io/last-applied-configuration": "{\\"data\\":{\\"password\\":\\"secret\\"}}"
                    },
                    "ownerReferences": [
                      {
                        "kind": "ReplicaSet",
                        "name": "web-74fbd884",
                        "controller": true
                      }
                    ]
                  },
                  "spec": {
                    "containers": [
                      {
                        "name": "web",
                        "image": "nginx:1.27",
                        "env": [
                          {
                            "name": "APP_ENV",
                            "value": "demo"
                          },
                          {
                            "name": "DB_PASSWORD",
                            "valueFrom": {
                              "secretKeyRef": {
                                "name": "web-secrets",
                                "key": "db-password"
                              }
                            }
                          },
                          {
                            "name": "POD_NAME",
                            "valueFrom": {
                              "fieldRef": {
                                "fieldPath": "metadata.name"
                              }
                            }
                          }
                        ],
                        "envFrom": [
                          {
                            "configMapRef": {
                              "name": "web-config"
                            }
                          },
                          {
                            "prefix": "EXTRA_",
                            "secretRef": {
                              "name": "web-extra-secrets",
                              "optional": true
                            }
                          }
                        ]
                      }
                    ]
                  },
                  "status": {
                    "phase": "Running",
                    "conditions": [
                      {
                        "type": "Ready",
                        "status": "True",
                        "reason": "ContainersReady",
                        "message": "All containers are ready.",
                        "lastTransitionTime": "2026-06-15T10:01:00Z"
                      }
                    ],
                    "containerStatuses": [
                      {
                        "name": "web",
                        "ready": true,
                        "restartCount": 1
                      }
                    ]
                  }
                }
                """.utf8
            )
        )

        let summary = detail.summary
        #expect(summary.apiVersion == "v1")
        #expect(summary.kind == "Pod")
        #expect(summary.name == "web-0")
        #expect(summary.namespace == "vibekube-demo")
        #expect(summary.uid == "pod-uid")
        #expect(summary.status == "Running")
        #expect(summary.labels["app"] == "web")
        #expect(summary.annotations["vibekube.io/demo"] == "true")
        #expect(summary.annotations["kubectl.kubernetes.io/last-applied-configuration"] == "<redacted>")
        #expect(summary.ownerReferences.first?.kind == "ReplicaSet")
        #expect(summary.ownerReferences.first?.controller == true)
        #expect(summary.conditions.first?.type == "Ready")
        #expect(summary.conditions.first?.status == "True")
        #expect(summary.containers.first?.name == "web")
        #expect(summary.containers.first?.ready == true)
        #expect(summary.containers.first?.restartCount == 1)
        #expect(summary.environment.first?.containerName == "web")
        #expect(summary.environment.first?.variables.first?.name == "APP_ENV")
        #expect(summary.environment.first?.variables.first?.literalValue == "demo")
        #expect(summary.environment.first?.variables[1].source?.kind == .secretKeyRef)
        #expect(summary.environment.first?.variables[1].source?.name == "web-secrets")
        #expect(summary.environment.first?.variables[1].source?.key == "db-password")
        #expect(summary.environment.first?.variables[2].source?.kind == .fieldRef)
        #expect(summary.environment.first?.variables[2].source?.fieldPath == "metadata.name")
        #expect(summary.environment.first?.envFrom.first?.kind == .configMapRef)
        #expect(summary.environment.first?.envFrom.first?.name == "web-config")
        #expect(summary.environment.first?.envFrom[1].kind == .secretRef)
        #expect(summary.environment.first?.envFrom[1].prefix == "EXTRA_")
        #expect(summary.environment.first?.envFrom[1].isOptional == true)
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
        #expect(detail.decodedSecretValue(forKey: "password") == "secret")
        #expect(detail.decodedSecretValue(forKey: "token") == "plain-token")
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
