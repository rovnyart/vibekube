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

    @Test func buildsPodLogQueryItems() {
        let options = KubernetesPodLogOptions(
            container: "web",
            previous: true,
            follow: false,
            tailLines: 200,
            sinceSeconds: 3_600,
            timestamps: true
        )

        let values = Dictionary(uniqueKeysWithValues: options.queryItems.map { ($0.name, $0.value) })
        #expect(values["container"] == "web")
        #expect(values["previous"] == "true")
        #expect(values["tailLines"] == "200")
        #expect(values["sinceSeconds"] == "3600")
        #expect(values["timestamps"] == "true")
        #expect(values["follow"] == nil)
    }

    @Test func decodesPodWatchEvent() throws {
        let event = try JSONDecoder().decode(
            KubernetesWatchEvent<KubernetesUnstructuredResource>.self,
            from: Data(
                """
                {
                  "type": "ADDED",
                  "object": {
                    "apiVersion": "v1",
                    "kind": "Pod",
                    "metadata": {
                      "name": "heartbeat-1",
                      "namespace": "vibekube-demo",
                      "uid": "heartbeat-uid",
                      "resourceVersion": "42"
                    },
                    "status": {
                      "phase": "Running"
                    }
                  }
                }
                """.utf8
            )
        )

        #expect(event.type == .added)
        #expect(event.object?.displayName == "heartbeat-1")
        #expect(event.object?.metadata.resourceVersion == "42")
        #expect(event.status == nil)
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

    @Test func podRowsPreferContainerWaitingReasonAndSumRestarts() throws {
        let list = try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "apiVersion": "v1",
                  "kind": "PodList",
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "crashy",
                        "namespace": "vibekube-demo"
                      },
                      "status": {
                        "phase": "Running",
                        "initContainerStatuses": [
                          {
                            "name": "prepare",
                            "restartCount": 1,
                            "state": {
                              "terminated": {
                                "reason": "Completed",
                                "exitCode": 0
                              }
                            }
                          }
                        ],
                        "containerStatuses": [
                          {
                            "name": "worker",
                            "restartCount": 3,
                            "state": {
                              "waiting": {
                                "reason": "CrashLoopBackOff"
                              }
                            }
                          },
                          {
                            "name": "sidecar",
                            "restartCount": 2,
                            "state": {
                              "running": {}
                            }
                          }
                        ]
                      }
                    },
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "missing-image",
                        "namespace": "vibekube-demo"
                      },
                      "status": {
                        "phase": "Pending",
                        "containerStatuses": [
                          {
                            "name": "app",
                            "restartCount": 0,
                            "state": {
                              "waiting": {
                                "reason": "ImagePullBackOff"
                              }
                            }
                          }
                        ]
                      }
                    }
                  ]
                }
                """.utf8
            )
        )

        #expect(list.items[0].displayStatus == "CrashLoopBackOff")
        #expect(list.items[0].podRestartCount == 6)
        #expect(list.items[0].podRestartCountDescription == "6")
        #expect(list.items[0].isPodUnhealthy)
        #expect(list.items[1].displayStatus == "ImagePullBackOff")
        #expect(list.items[1].podRestartCount == 0)
        #expect(list.items[1].isPodUnhealthy)
    }

    @Test func mergesResourceListPagesInOrder() throws {
        let first = try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "apiVersion": "v1",
                  "kind": "PodList",
                  "metadata": {
                    "resourceVersion": "10",
                    "continue": "next"
                  },
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "web-0",
                        "namespace": "default"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
        let second = try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "apiVersion": "v1",
                  "kind": "PodList",
                  "metadata": {
                    "resourceVersion": "20"
                  },
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "api-0",
                        "namespace": "payments"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )

        let merged = KubernetesUnstructuredResourceList.merged([first, second])

        #expect(merged.metadata?.resourceVersion == "20")
        #expect(merged.metadata?.continueToken == nil)
        #expect(merged.items.map(\.displayName) == ["web-0", "api-0"])
    }

    @Test func preservesExistingRowOrderWhileUserIsInspectingAResource() throws {
        let list = try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "api",
                        "namespace": "default"
                      },
                      "status": {
                        "phase": "Running"
                      }
                    },
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "worker",
                        "namespace": "default"
                      },
                      "status": {
                        "phase": "Pending"
                      }
                    },
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "cron",
                        "namespace": "default"
                      },
                      "status": {
                        "phase": "Succeeded"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )

        let sortedRows = ResourceListRowOrdering.orderedRows(
            list.items,
            sortOrder: [KeyPathComparator(\.displayStatus)],
            preservedOrderIDs: [],
            preserveExistingOrder: false
        )
        let preservedRows = ResourceListRowOrdering.orderedRows(
            list.items,
            sortOrder: [KeyPathComparator(\.displayStatus)],
            preservedOrderIDs: Array(list.items.prefix(2)).map(\.id),
            preserveExistingOrder: true
        )

        #expect(sortedRows.map(\.displayName) == ["worker", "api", "cron"])
        #expect(preservedRows.map(\.displayName) == ["api", "worker", "cron"])
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

    @Test func decodesDashboardEventRowDetails() throws {
        let list = try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "apiVersion": "events.k8s.io/v1",
                      "kind": "Event",
                      "metadata": {
                        "name": "web.18b95677",
                        "namespace": "vibekube-demo",
                        "uid": "event-uid",
                        "creationTimestamp": "2026-06-15T10:00:00Z"
                      },
                      "type": "Normal",
                      "reason": "Started",
                      "note": "Started container web",
                      "deprecatedCount": 3,
                      "deprecatedLastTimestamp": "2026-06-15T10:01:00Z",
                      "reportingController": "kubelet",
                      "reportingInstance": "kind-control-plane",
                      "regarding": {
                        "kind": "Pod",
                        "name": "web-0",
                        "namespace": "vibekube-demo",
                        "fieldPath": "spec.containers{web}"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )

        let event = try #require(list.items.first)
        #expect(event.displayStatus == "Normal Started")
        #expect(event.eventMessage == "Started container web")
        #expect(event.eventCount == 3)
        #expect(event.eventSourceDescription == "kubelet / kind-control-plane")
        #expect(event.eventInvolvedObjectDescription == "Pod / vibekube-demo / web-0 / spec.containers{web}")
        #expect(event.searchBlob.contains("started container web"))
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
                    "initContainers": [
                      {
                        "name": "migrate",
                        "image": "busybox:1.36"
                      }
                    ],
                    "containers": [
                      {
                        "name": "web",
                        "image": "nginx:1.27",
                        "imagePullPolicy": "IfNotPresent",
                        "resources": {
                          "requests": {
                            "cpu": "100m",
                            "memory": "128Mi"
                          },
                          "limits": {
                            "memory": "256Mi"
                          }
                        },
                        "readinessProbe": {
                          "httpGet": {
                            "path": "/healthz",
                            "port": 8080
                          },
                          "initialDelaySeconds": 3,
                          "periodSeconds": 10,
                          "failureThreshold": 2
                        },
                        "livenessProbe": {
                          "tcpSocket": {
                            "port": "http"
                          },
                          "periodSeconds": 20
                        },
                        "volumeMounts": [
                          {
                            "name": "config",
                            "mountPath": "/etc/web",
                            "readOnly": true
                          }
                        ],
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
                    "initContainerStatuses": [
                      {
                        "name": "migrate",
                        "restartCount": 0,
                        "state": {
                          "terminated": {
                            "reason": "Completed",
                            "exitCode": 0,
                            "startedAt": "2026-06-15T10:00:10Z",
                            "finishedAt": "2026-06-15T10:00:20Z"
                          }
                        }
                      }
                    ],
                    "containerStatuses": [
                      {
                        "name": "web",
                        "imageID": "docker-pullable://nginx@sha256:abc",
                        "containerID": "containerd://web123",
                        "ready": true,
                        "started": true,
                        "restartCount": 1,
                        "state": {
                          "running": {
                            "startedAt": "2026-06-15T10:01:00Z"
                          }
                        },
                        "lastState": {
                          "terminated": {
                            "reason": "Error",
                            "message": "previous process failed",
                            "exitCode": 137,
                            "finishedAt": "2026-06-15T10:00:55Z"
                          }
                        }
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
        #expect(summary.containers.count == 2)
        #expect(summary.containers.first?.name == "migrate")
        #expect(summary.containers.first?.kind == .initContainer)
        #expect(summary.containers.first?.currentState?.kind == .terminated)
        #expect(summary.containers.first?.currentState?.exitCode == 0)
        #expect(summary.containers[1].name == "web")
        #expect(summary.containers[1].kind == .container)
        #expect(summary.containers[1].imagePullPolicy == "IfNotPresent")
        #expect(summary.containers[1].imageID == "docker-pullable://nginx@sha256:abc")
        #expect(summary.containers[1].containerID == "containerd://web123")
        #expect(summary.containers[1].ready == true)
        #expect(summary.containers[1].started == true)
        #expect(summary.containers[1].restartCount == 1)
        #expect(summary.containers[1].currentState?.kind == .running)
        #expect(summary.containers[1].currentState?.startedAt == "2026-06-15T10:01:00Z")
        #expect(summary.containers[1].lastState?.kind == .terminated)
        #expect(summary.containers[1].lastState?.reason == "Error")
        #expect(summary.containers[1].lastState?.message == "previous process failed")
        #expect(summary.containers[1].lastState?.exitCode == 137)
        #expect(summary.containers[1].resources.requests["cpu"] == "100m")
        #expect(summary.containers[1].resources.limits["memory"] == "256Mi")
        #expect(summary.containers[1].probes.count == 2)
        #expect(summary.containers[1].probes.first?.kind == .readiness)
        #expect(summary.containers[1].probes.first?.handler == "HTTP /healthz :8080")
        #expect(summary.containers[1].probes.first?.failureThreshold == 2)
        #expect(summary.containers[1].volumeMounts.first?.name == "config")
        #expect(summary.containers[1].volumeMounts.first?.mountPath == "/etc/web")
        #expect(summary.containers[1].volumeMounts.first?.readOnly == true)
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

    @Test func decodesCoreAndEventsAPIResourceEvents() throws {
        let list = try JSONDecoder().decode(
            KubernetesResourceEventList.self,
            from: Data(
                """
                {
                  "apiVersion": "v1",
                  "kind": "EventList",
                  "metadata": {
                    "resourceVersion": "123"
                  },
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Event",
                      "metadata": {
                        "name": "web.older",
                        "namespace": "vibekube-demo",
                        "uid": "event-older",
                        "creationTimestamp": "2026-06-15T10:00:00Z"
                      },
                      "type": "Warning",
                      "reason": "FailedScheduling",
                      "message": "No nodes were available.",
                      "count": 2,
                      "lastTimestamp": "2026-06-15T10:00:00Z",
                      "source": {
                        "component": "default-scheduler"
                      },
                      "involvedObject": {
                        "kind": "Pod",
                        "name": "web-0",
                        "namespace": "vibekube-demo",
                        "uid": "pod-uid"
                      }
                    },
                    {
                      "apiVersion": "events.k8s.io/v1",
                      "kind": "Event",
                      "metadata": {
                        "name": "web.newer",
                        "namespace": "vibekube-demo",
                        "uid": "event-newer",
                        "creationTimestamp": "2026-06-15T10:01:00Z"
                      },
                      "type": "Normal",
                      "reason": "Pulled",
                      "note": "Container image is present.",
                      "deprecatedCount": 1,
                      "eventTime": "2026-06-15T10:01:00Z",
                      "reportingController": "kubelet",
                      "reportingInstance": "kind-control-plane",
                      "regarding": {
                        "kind": "Pod",
                        "name": "web-0",
                        "namespace": "vibekube-demo",
                        "uid": "pod-uid",
                        "fieldPath": "spec.containers{web}"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )

        #expect(list.metadata?.resourceVersion == "123")
        #expect(list.summaries.map(\.reason) == ["Pulled", "FailedScheduling"])
        #expect(list.summaries.first?.message == "Container image is present.")
        #expect(list.summaries.first?.source == "kubelet / kind-control-plane")
        #expect(list.summaries.first?.involvedFieldPath == "spec.containers{web}")
        #expect(list.summaries.last?.type == "Warning")
        #expect(list.summaries.last?.count == 2)
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

    @Test func dashboardSnapshotComputesNodePodAndWorkloadHealth() throws {
        let snapshot = try ClusterDashboardSnapshot.make(states: [
            .nodes: loadedState(
                for: .nodes,
                json:
                """
                {
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Node",
                      "metadata": { "name": "ready-node" },
                      "status": {
                        "conditions": [
                          { "type": "Ready", "status": "True" }
                        ]
                      }
                    },
                    {
                      "apiVersion": "v1",
                      "kind": "Node",
                      "metadata": { "name": "not-ready-node" },
                      "status": {
                        "conditions": [
                          { "type": "Ready", "status": "False" }
                        ]
                      }
                    },
                    {
                      "apiVersion": "v1",
                      "kind": "Node",
                      "metadata": { "name": "unknown-node" },
                      "status": { "conditions": [] }
                    }
                  ]
                }
                """
            ),
            .pods: loadedState(
                for: .pods,
                json:
                """
                {
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": { "name": "running", "namespace": "demo" },
                      "status": {
                        "phase": "Running",
                        "containerStatuses": [
                          { "name": "app", "restartCount": 2 }
                        ]
                      }
                    },
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": { "name": "pending", "namespace": "demo" },
                      "status": { "phase": "Pending" }
                    },
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": { "name": "failed", "namespace": "demo" },
                      "status": { "phase": "Failed" }
                    },
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": { "name": "succeeded", "namespace": "demo" },
                      "status": { "phase": "Succeeded" }
                    },
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": { "name": "mystery", "namespace": "demo" },
                      "status": { "phase": "Mystery" }
                    }
                  ]
                }
                """
            ),
            .deployments: loadedState(
                for: .deployments,
                json:
                """
                {
                  "items": [
                    {
                      "apiVersion": "apps/v1",
                      "kind": "Deployment",
                      "metadata": { "name": "ready", "namespace": "demo" },
                      "spec": { "replicas": 2 },
                      "status": { "readyReplicas": 2 }
                    },
                    {
                      "apiVersion": "apps/v1",
                      "kind": "Deployment",
                      "metadata": { "name": "progressing", "namespace": "demo" },
                      "spec": { "replicas": 3 },
                      "status": { "readyReplicas": 1 }
                    },
                    {
                      "apiVersion": "apps/v1",
                      "kind": "Deployment",
                      "metadata": { "name": "unavailable", "namespace": "demo" },
                      "spec": { "replicas": 2 },
                      "status": { "readyReplicas": 0 }
                    }
                  ]
                }
                """
            )
        ])

        #expect(snapshot.nodeHealth.total == 3)
        #expect(snapshot.resourceCount(for: .nodes) == 3)
        #expect(snapshot.nodeHealth.ready == 1)
        #expect(snapshot.nodeHealth.notReady == 1)
        #expect(snapshot.nodeHealth.unknown == 1)
        #expect(snapshot.nodeHealth.status == .failed)

        #expect(snapshot.podHealth.total == 5)
        #expect(snapshot.resourceCount(for: .pods) == 5)
        #expect(snapshot.podHealth.running == 1)
        #expect(snapshot.podHealth.pending == 1)
        #expect(snapshot.podHealth.failed == 1)
        #expect(snapshot.podHealth.succeeded == 1)
        #expect(snapshot.podHealth.unknown == 1)
        #expect(snapshot.podHealth.restartCount == 2)
        #expect(snapshot.podHealth.status == .failed)

        #expect(snapshot.workloadHealth.total == 3)
        #expect(snapshot.resourceCount(for: .deployments) == 3)
        #expect(snapshot.workloadHealth.ready == 1)
        #expect(snapshot.workloadHealth.progressing == 1)
        #expect(snapshot.workloadHealth.unavailable == 1)
        #expect(snapshot.workloadHealth.status == .failed)
        #expect(snapshot.status == .failed)
    }

    @Test func dashboardSnapshotAggregatesWarningEvents() throws {
        let snapshot = try ClusterDashboardSnapshot.make(states: [
            .events: loadedState(
                for: .events,
                json:
                """
                {
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Event",
                      "metadata": { "name": "first", "namespace": "demo" },
                      "type": "Warning",
                      "reason": "FailedScheduling",
                      "message": "No nodes available.",
                      "count": 2,
                      "source": { "component": "default-scheduler" },
                      "involvedObject": {
                        "kind": "Pod",
                        "namespace": "demo",
                        "name": "api"
                      }
                    },
                    {
                      "apiVersion": "v1",
                      "kind": "Event",
                      "metadata": { "name": "second", "namespace": "demo" },
                      "type": "Warning",
                      "reason": "FailedScheduling",
                      "message": "No nodes available.",
                      "count": 3,
                      "source": { "component": "default-scheduler" },
                      "involvedObject": {
                        "kind": "Pod",
                        "namespace": "demo",
                        "name": "api"
                      }
                    },
                    {
                      "apiVersion": "v1",
                      "kind": "Event",
                      "metadata": { "name": "third", "namespace": "demo" },
                      "type": "Warning",
                      "reason": "FailedMount",
                      "message": "Volume not ready.",
                      "count": 1,
                      "source": { "component": "kubelet", "host": "worker-1" },
                      "involvedObject": {
                        "kind": "Pod",
                        "namespace": "demo",
                        "name": "worker"
                      }
                    },
                    {
                      "apiVersion": "v1",
                      "kind": "Event",
                      "metadata": { "name": "normal", "namespace": "demo" },
                      "type": "Normal",
                      "reason": "Pulled",
                      "message": "Image is present.",
                      "count": 1
                    }
                  ]
                }
                """
            )
        ])

        #expect(snapshot.eventHealth.isLoaded)
        #expect(snapshot.eventHealth.total == 4)
        #expect(snapshot.eventHealth.warnings == 3)
        #expect(snapshot.eventHealth.status == .warning)
        #expect(snapshot.eventHealth.topWarnings.first?.reason == "FailedScheduling")
        #expect(snapshot.eventHealth.topWarnings.first?.count == 5)
        #expect(snapshot.status == .warning)
    }

    @Test func dashboardSnapshotComputesStorageAndEmptyLoadedWorkloads() throws {
        let snapshot = try ClusterDashboardSnapshot.make(states: [
            .deployments: loadedState(for: .deployments, json: #"{ "items": [] }"#),
            .persistentVolumes: loadedState(
                for: .persistentVolumes,
                json:
                """
                {
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "PersistentVolume",
                      "metadata": { "name": "pv-bound" },
                      "status": { "phase": "Bound" }
                    },
                    {
                      "apiVersion": "v1",
                      "kind": "PersistentVolume",
                      "metadata": { "name": "pv-available" },
                      "status": { "phase": "Available" }
                    }
                  ]
                }
                """
            ),
            .persistentVolumeClaims: loadedState(
                for: .persistentVolumeClaims,
                json:
                """
                {
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "PersistentVolumeClaim",
                      "metadata": { "name": "pvc-pending", "namespace": "demo" },
                      "status": { "phase": "Pending" }
                    },
                    {
                      "apiVersion": "v1",
                      "kind": "PersistentVolumeClaim",
                      "metadata": { "name": "pvc-lost", "namespace": "demo" },
                      "status": { "phase": "Lost" }
                    }
                  ]
                }
                """
            )
        ])

        #expect(snapshot.workloadHealth.isLoaded)
        #expect(snapshot.workloadHealth.total == 0)
        #expect(snapshot.workloadHealth.status == .unknown)

        #expect(snapshot.storageHealth.isLoaded)
        #expect(snapshot.storageHealth.total == 4)
        #expect(snapshot.storageHealth.bound == 2)
        #expect(snapshot.storageHealth.pending == 1)
        #expect(snapshot.storageHealth.lost == 1)
        #expect(snapshot.storageHealth.status == .failed)
        #expect(snapshot.status == .failed)
    }

    @Test func dashboardSnapshotIgnoresUnknownSectionsWhenKnownHealthExists() throws {
        let snapshot = try ClusterDashboardSnapshot.make(states: [
            .pods: loadedState(
                for: .pods,
                json:
                """
                {
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": { "name": "running", "namespace": "demo" },
                      "status": { "phase": "Running" }
                    }
                  ]
                }
                """
            )
        ])

        #expect(snapshot.podHealth.status == .healthy)
        #expect(snapshot.nodeHealth.status == .unknown)
        #expect(snapshot.storageHealth.status == .unknown)
        #expect(snapshot.status == .healthy)
    }

    @Test func metricsQuantityParsesCPUAndMemoryUnits() {
        #expect(KubernetesMetricsQuantity(rawValue: "750m").cpuMillicores == 750)
        #expect(KubernetesMetricsQuantity(rawValue: "1").cpuMillicores == 1_000)
        #expect(KubernetesMetricsQuantity(rawValue: "250000000n").cpuMillicores == 250)
        #expect(KubernetesMetricsQuantity(rawValue: "125000u").cpuMillicores == 125)

        #expect(KubernetesMetricsQuantity(rawValue: "512Mi").memoryBytes == Double(512 * 1024 * 1024))
        #expect(KubernetesMetricsQuantity(rawValue: "2Gi").memoryBytes == Double(2 * 1024 * 1024 * 1024))
        #expect(KubernetesMetricsQuantity(rawValue: "100M").memoryBytes == Double(100 * 1000 * 1000))
    }

    @Test func dashboardResourceUsageSummaryComputesCPUAndMemoryUsage() throws {
        let nodes = try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Node",
                      "metadata": { "name": "node-1" },
                      "status": {
                        "allocatable": {
                          "cpu": "2",
                          "memory": "4Gi"
                        }
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
        let nodeMetrics = try JSONDecoder().decode(
            KubernetesNodeMetricsList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "metadata": { "name": "node-1" },
                      "usage": {
                        "cpu": "500m",
                        "memory": "1024Mi"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
        let podMetrics = try JSONDecoder().decode(
            KubernetesPodMetricsList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "metadata": {
                        "name": "pod-1",
                        "namespace": "demo"
                      },
                      "containers": [
                        {
                          "name": "app",
                          "usage": {
                            "cpu": "250m",
                            "memory": "256Mi"
                          }
                        }
                      ]
                    }
                  ]
                }
                """.utf8
            )
        )

        let summary = DashboardResourceUsageSummary.make(
            state: .loaded(
                DashboardMetricsSnapshot(
                    query: DashboardMetricsQuery(contextID: "test", namespaceSelection: AppModel.allNamespacesSelection),
                    nodeMetrics: nodeMetrics.items,
                    podMetrics: podMetrics.items,
                    loadedAt: Date(timeIntervalSince1970: 0)
                )
            ),
            nodeItems: nodes.items
        )

        #expect(summary.cpuUsageMillicores == 500)
        #expect(summary.cpuCapacityMillicores == 2_000)
        #expect(summary.cpuUsageFraction == 0.25)
        #expect(summary.memoryUsageBytes == Double(1024 * 1024 * 1024))
        #expect(summary.memoryCapacityBytes == Double(4 * 1024 * 1024 * 1024))
        #expect(summary.memoryUsageFraction == 0.25)
        #expect(summary.nodeMetricsCount == 1)
        #expect(summary.podMetricsCount == 1)
        #expect(summary.usesClusterNodeMetrics)
    }

    @Test func dashboardResourceUsageSummaryUsesPodMetricsForNamespaceScope() throws {
        let nodeMetrics = try JSONDecoder().decode(
            KubernetesNodeMetricsList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "metadata": { "name": "node-1" },
                      "usage": {
                        "cpu": "500m",
                        "memory": "1024Mi"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
        let podMetrics = try JSONDecoder().decode(
            KubernetesPodMetricsList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "metadata": {
                        "name": "pod-1",
                        "namespace": "demo"
                      },
                      "containers": [
                        {
                          "name": "app",
                          "usage": {
                            "cpu": "250m",
                            "memory": "256Mi"
                          }
                        }
                      ]
                    }
                  ]
                }
                """.utf8
            )
        )

        let summary = DashboardResourceUsageSummary.make(
            state: .loaded(
                DashboardMetricsSnapshot(
                    query: DashboardMetricsQuery(contextID: "test", namespaceSelection: "demo"),
                    nodeMetrics: nodeMetrics.items,
                    podMetrics: podMetrics.items,
                    loadedAt: Date(timeIntervalSince1970: 0)
                )
            ),
            nodeItems: []
        )

        #expect(summary.cpuUsageMillicores == 250)
        #expect(summary.cpuCapacityMillicores == nil)
        #expect(summary.memoryUsageBytes == Double(256 * 1024 * 1024))
        #expect(summary.memoryCapacityBytes == nil)
        #expect(!summary.usesClusterNodeMetrics)
    }

    private func loadedState(
        for item: ResourceNavigationItem,
        json: String
    ) throws -> ResourceListLoadState {
        let list = try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(json.utf8)
        )
        let resource = discoveredResource(for: item)
        return .loaded(
            ResourceListSnapshot(
                query: ResourceListQuery(
                    contextID: "test",
                    resource: resource,
                    namespaceSelection: AppModel.allNamespacesSelection
                ),
                items: list.items,
                resourceVersion: list.metadata?.resourceVersion,
                continueToken: list.metadata?.continueToken,
                loadedAt: Date(timeIntervalSince1970: 0)
            )
        )
    }

    private func discoveredResource(for item: ResourceNavigationItem) -> KubernetesDiscoveredResource {
        let definition: (groupVersion: String, name: String, kind: String, namespaced: Bool)
        switch item {
        case .nodes:
            definition = ("v1", "nodes", "Node", false)
        case .pods:
            definition = ("v1", "pods", "Pod", true)
        case .deployments:
            definition = ("apps/v1", "deployments", "Deployment", true)
        case .statefulSets:
            definition = ("apps/v1", "statefulsets", "StatefulSet", true)
        case .daemonSets:
            definition = ("apps/v1", "daemonsets", "DaemonSet", true)
        case .jobs:
            definition = ("batch/v1", "jobs", "Job", true)
        case .cronJobs:
            definition = ("batch/v1", "cronjobs", "CronJob", true)
        case .persistentVolumes:
            definition = ("v1", "persistentvolumes", "PersistentVolume", false)
        case .persistentVolumeClaims:
            definition = ("v1", "persistentvolumeclaims", "PersistentVolumeClaim", true)
        case .events:
            definition = ("v1", "events", "Event", true)
        default:
            definition = ("v1", item.rawValue, item.title, true)
        }

        return KubernetesDiscoveredResource(
            groupVersion: definition.groupVersion,
            resource: KubernetesAPIResource(
                name: definition.name,
                singularName: "",
                namespaced: definition.namespaced,
                kind: definition.kind,
                verbs: ["get", "list"],
                shortNames: nil,
                categories: nil
            )
        )
    }
}
