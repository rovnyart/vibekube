import Foundation
import Testing
@testable import vibekube

@MainActor
struct KubernetesMutationPreviewTests {
    @Test func previewsExistingResourceWithDryRunAndDiff() async throws {
        let resource = deploymentResource()
        let live = try resourceDetail(
            """
            {
              "apiVersion": "apps/v1",
              "kind": "Deployment",
              "metadata": {
                "name": "echo-web",
                "namespace": "vibekube-demo",
                "resourceVersion": "10"
              },
              "spec": {
                "replicas": 1
              }
            }
            """
        )
        let dryRun = try resourceDetail(
            """
            {
              "apiVersion": "apps/v1",
              "kind": "Deployment",
              "metadata": {
                "name": "echo-web",
                "namespace": "vibekube-demo",
                "resourceVersion": "11"
              },
              "spec": {
                "replicas": 3
              }
            }
            """
        )
        let mutationService = RecordingMutationService { request in
            #expect(request.verb == .put)
            #expect(request.resource == resource)
            #expect(request.namespace == "vibekube-demo")
            #expect(request.name == "echo-web")
            #expect(request.dryRun)
            #expect(request.contentType == "application/json")

            let body = try #require(request.body)
            let value = try JSONDecoder().decode(KubernetesJSONValue.self, from: body)
            #expect(value["spec"]?["replicas"]?.intValue == 3)
            return KubernetesMutationResult(statusCode: 200, status: nil, resource: dryRun)
        }
        let previewService = KubernetesMutationPreviewService(
            mutationService: mutationService,
            resourceDetailService: StaticResourceDetailService(detail: live)
        )

        let preview = try await previewService.previewExistingResource(
            contextName: "demo",
            kubeconfig: kubeconfig(),
            resource: resource,
            namespace: "vibekube-demo",
            name: "echo-web",
            proposedYAML: """
            apiVersion: apps/v1
            kind: Deployment
            metadata:
              name: echo-web
              namespace: vibekube-demo
              resourceVersion: "10"
            spec:
              replicas: 3
            """
        )

        #expect(preview.mutationRequest.dryRun)
        #expect(preview.proposedResource.summary.name == "echo-web")
        #expect(preview.dryRunResource.summary.resourceVersion == "11")
        #expect(preview.diff.hasChanges)
        #expect(preview.diff.unifiedText.contains("-   replicas: 1"))
        #expect(preview.diff.unifiedText.contains("+   replicas: 3"))
        #expect(await mutationService.requestCount() == 1)
    }

    @Test func rejectsInvalidYAMLBeforeDryRun() async throws {
        let mutationService = RecordingMutationService { _ in
            Issue.record("Dry-run should not be called for invalid YAML")
            return KubernetesMutationResult(statusCode: 200, status: nil, resource: nil)
        }
        let previewService = KubernetesMutationPreviewService(
            mutationService: mutationService,
            resourceDetailService: StaticResourceDetailService(detail: try resourceDetail("{}"))
        )

        do {
            _ = try await previewService.previewExistingResource(
                contextName: "demo",
                kubeconfig: kubeconfig(),
                resource: deploymentResource(),
                namespace: "vibekube-demo",
                name: "echo-web",
                proposedYAML: """
                apiVersion: apps/v1
                  kind: Deployment
                """
            )
            Issue.record("Expected invalid YAML")
        } catch let error as KubernetesMutationPreviewError {
            guard case .invalidYAML = error else {
                Issue.record("Expected invalid YAML, got \(error)")
                return
            }
        }

        #expect(await mutationService.requestCount() == 0)
    }

    @Test func rejectsNamespaceMismatchBeforeDryRun() async throws {
        let mutationService = RecordingMutationService { _ in
            Issue.record("Dry-run should not be called for namespace mismatch")
            return KubernetesMutationResult(statusCode: 200, status: nil, resource: nil)
        }
        let previewService = KubernetesMutationPreviewService(
            mutationService: mutationService,
            resourceDetailService: StaticResourceDetailService(detail: try resourceDetail("{}"))
        )

        do {
            _ = try await previewService.previewExistingResource(
                contextName: "demo",
                kubeconfig: kubeconfig(),
                resource: deploymentResource(),
                namespace: "vibekube-demo",
                name: "echo-web",
                proposedYAML: """
                apiVersion: apps/v1
                kind: Deployment
                metadata:
                  name: echo-web
                  namespace: other
                spec:
                  replicas: 3
                """
            )
            Issue.record("Expected namespace mismatch")
        } catch let error as KubernetesMutationPreviewError {
            guard case .identityMismatch(let field, let expected, let actual) = error else {
                Issue.record("Expected identity mismatch, got \(error)")
                return
            }
            #expect(field == "metadata.namespace")
            #expect(expected == "vibekube-demo")
            #expect(actual == "other")
        }

        #expect(await mutationService.requestCount() == 0)
    }

    @Test func surfacesDryRunValidationCauses() async throws {
        let status = KubernetesStatus(
            kind: "Status",
            apiVersion: "v1",
            status: "Failure",
            message: "Deployment.apps \"echo-web\" is invalid",
            reason: "Invalid",
            details: KubernetesStatusDetails(
                name: "echo-web",
                group: "apps",
                kind: "Deployment",
                uid: nil,
                causes: [
                    KubernetesStatusCause(
                        reason: "FieldValueInvalid",
                        message: "Invalid value: -1",
                        field: "spec.replicas"
                    )
                ],
                retryAfterSeconds: nil
            ),
            code: 422
        )
        let previewService = KubernetesMutationPreviewService(
            mutationService: RecordingMutationService { _ in
                throw KubernetesMutationError.status(status, httpStatusCode: 422)
            },
            resourceDetailService: StaticResourceDetailService(detail: try liveDeployment())
        )

        do {
            _ = try await previewService.previewExistingResource(
                contextName: "demo",
                kubeconfig: kubeconfig(),
                resource: deploymentResource(),
                namespace: "vibekube-demo",
                name: "echo-web",
                proposedYAML: validDeploymentYAML(replicas: -1)
            )
            Issue.record("Expected validation error")
        } catch let error as KubernetesMutationPreviewError {
            guard case .serverRejected(let mutationError) = error else {
                Issue.record("Expected server rejection, got \(error)")
                return
            }
            #expect(mutationError.isValidationFailure)
            #expect(error.fieldCauses.first?.field == "spec.replicas")
        }
    }

    @Test func mapsDryRunConflictToRetryablePreviewError() async throws {
        let status = KubernetesStatus(
            kind: "Status",
            apiVersion: "v1",
            status: "Failure",
            message: "Operation cannot be fulfilled on deployments.apps \"echo-web\"",
            reason: "Conflict",
            details: KubernetesStatusDetails(
                name: "echo-web",
                group: "apps",
                kind: "Deployment",
                uid: nil,
                causes: nil,
                retryAfterSeconds: 2
            ),
            code: 409
        )
        let previewService = KubernetesMutationPreviewService(
            mutationService: RecordingMutationService { _ in
                throw KubernetesMutationError.status(status, httpStatusCode: 409)
            },
            resourceDetailService: StaticResourceDetailService(detail: try liveDeployment())
        )

        do {
            _ = try await previewService.previewExistingResource(
                contextName: "demo",
                kubeconfig: kubeconfig(),
                resource: deploymentResource(),
                namespace: "vibekube-demo",
                name: "echo-web",
                proposedYAML: validDeploymentYAML(replicas: 3)
            )
            Issue.record("Expected conflict")
        } catch let error as KubernetesMutationPreviewError {
            guard case .conflict(let conflict) = error else {
                Issue.record("Expected conflict, got \(error)")
                return
            }
            #expect(conflict.retryAfterSeconds == 2)
            #expect(conflict.message.contains("Conflict"))
        }
    }

    @Test func previewsRenderedManifestWithManagedFieldsAndResourceQuantities() async throws {
        let resource = deploymentResource()
        let live = try resourceDetail(
            """
            {
              "apiVersion": "apps/v1",
              "kind": "Deployment",
              "metadata": {
                "name": "echo-web",
                "namespace": "vibekube-demo",
                "resourceVersion": "10",
                "managedFields": [
                  {
                    "manager": "kubectl",
                    "operation": "Apply",
                    "apiVersion": "apps/v1",
                    "fieldsV1": {
                      "f:metadata": {
                        "f:labels": {
                          "k:{\\"app\\":\\"echo-web\\"}": {}
                        }
                      },
                      "f:spec": {
                        "f:template": {
                          "f:spec": {
                            "f:containers": {
                              "k:{\\"name\\":\\"web\\"}": {
                                ".": {},
                                "f:resources": {}
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                ]
              },
              "spec": {
                "template": {
                  "spec": {
                    "containers": [
                      {
                        "name": "web",
                        "image": "nginx",
                        "resources": {
                          "requests": {
                            "cpu": "64m",
                            "memory": "64Mi"
                          }
                        }
                      }
                    ]
                  }
                }
              }
            }
            """
        )
        let dryRun = try resourceDetail(
            """
            {
              "apiVersion": "apps/v1",
              "kind": "Deployment",
              "metadata": {
                "name": "echo-web",
                "namespace": "vibekube-demo",
                "resourceVersion": "11"
              },
              "spec": {
                "template": {
                  "spec": {
                    "containers": [
                      {
                        "name": "web",
                        "image": "nginx",
                        "resources": {
                          "requests": {
                            "cpu": "128m",
                            "memory": "128Mi"
                          }
                        }
                      }
                    ]
                  }
                }
              }
            }
            """
        )
        let mutationService = RecordingMutationService { request in
            let body = try #require(request.body)
            let value = try JSONDecoder().decode(KubernetesJSONValue.self, from: body)
            let container = value["spec"]?["template"]?["spec"]?["containers"]?.arrayValue?.first
            let cpu = container?["resources"]?["requests"]?["cpu"]?.stringValue
            let memory = container?["resources"]?["requests"]?["memory"]?.stringValue
            #expect(cpu == "128m")
            #expect(memory == "128Mi")
            return KubernetesMutationResult(statusCode: 200, status: nil, resource: dryRun)
        }
        let previewService = KubernetesMutationPreviewService(
            mutationService: mutationService,
            resourceDetailService: StaticResourceDetailService(detail: live)
        )

        let proposedYAML = live.yaml
            .replacingOccurrences(of: "cpu: 64m", with: "cpu: 128m")
            .replacingOccurrences(of: "memory: 64Mi", with: "memory: 128Mi")
        #expect(proposedYAML.contains(#"resourceVersion: "10""#))
        #expect(proposedYAML.contains(#""k:{\"name\":\"web\"}":"#))
        #expect(proposedYAML.contains("cpu: 128m"))
        #expect(proposedYAML.contains("memory: 128Mi"))

        let preview = try await previewService.previewExistingResource(
            contextName: "demo",
            kubeconfig: kubeconfig(),
            resource: resource,
            namespace: "vibekube-demo",
            name: "echo-web",
            proposedYAML: proposedYAML
        )

        #expect(preview.diff.hasChanges)
        #expect(await mutationService.requestCount() == 1)
    }

    @Test func parserHandlesRenderedManagedFieldsKeys() throws {
        var parser = SimpleYAMLParser()

        let value = try parser.parse(
            """
            fieldsV1:
              f:spec:
                f:template:
                  f:spec:
                    f:containers:
                      "k:{\\"name\\":\\"web\\"}":
                        ".":
                          {}
                        f:resources:
                          {}
            """
        )

        let fields = try #require(value.mapping?["fieldsV1"]?.mapping)
        let containerFields = fields["f:spec"]?
            .mapping?["f:template"]?
            .mapping?["f:spec"]?
            .mapping?["f:containers"]?
            .mapping
        #expect(containerFields?["k:{\"name\":\"web\"}"] != nil)
        #expect(containerFields?["k:{\"name\":\"web\"}"]?.mapping?["."] == .mapping([:]))
    }

    @Test func parserPreservesQuotedScalarTypes() throws {
        var parser = SimpleYAMLParser()

        let value = try parser.parse(
            """
            metadata:
              resourceVersion: "162027"
            status:
              conditions:
                -
                  status: "True"
            spec:
              divisor: "0"
              replicas: 2
            """
        )

        let root = try #require(value.mapping)
        #expect(root["metadata"]?.mapping?["resourceVersion"] == .quotedScalar("162027"))
        let condition = root["status"]?
            .mapping?["conditions"]?
            .sequence?
            .first?
            .mapping
        #expect(condition?["status"] == .quotedScalar("True"))
        #expect(root["spec"]?.mapping?["divisor"] == .quotedScalar("0"))
        #expect(root["spec"]?.mapping?["replicas"] == .scalar("2"))
    }

    @Test func parserHandlesBlockScalarsFromKubectlYAML() throws {
        var parser = SimpleYAMLParser()

        let value = try parser.parse(
            """
            metadata:
              annotations:
                kubectl.kubernetes.io/last-applied-configuration: |
                  {"kind":"Deployment"}
            spec:
              initContainers:
                -
                  command:
                    - /bin/sh
                    - -c
                    - |
                      echo prepared
                      echo done
            """
        )

        let root = try #require(value.mapping)
        let annotation = root["metadata"]?
            .mapping?["annotations"]?
            .mapping?["kubectl.kubernetes.io/last-applied-configuration"]
        #expect(annotation == .quotedScalar(#"{"kind":"Deployment"}"# + "\n"))

        let command = root["spec"]?
            .mapping?["initContainers"]?
            .sequence?
            .first?
            .mapping?["command"]?
            .sequence
        #expect(command?[2] == .quotedScalar("echo prepared\necho done\n"))
    }

    @Test func parserHandlesBlockScalarChompingIndicators() throws {
        var parser = SimpleYAMLParser()

        let value = try parser.parse(
            """
            data:
              script: |-
                echo prepared
                echo done
              summary: >-
                deployment
                updated
            """
        )

        let data = try #require(value.mapping?["data"]?.mapping)
        #expect(data["script"] == .quotedScalar("echo prepared\necho done"))
        #expect(data["summary"] == .quotedScalar("deployment updated"))
    }

    private func deploymentResource() -> KubernetesDiscoveredResource {
        KubernetesDiscoveredResource(
            groupVersion: "apps/v1",
            resource: KubernetesAPIResource(
                name: "deployments",
                singularName: "",
                namespaced: true,
                kind: "Deployment",
                verbs: ["get", "list", "watch", "update", "patch"],
                shortNames: nil,
                categories: nil
            )
        )
    }

    private func liveDeployment() throws -> KubernetesResourceDetail {
        try resourceDetail(
            """
            {
              "apiVersion": "apps/v1",
              "kind": "Deployment",
              "metadata": {
                "name": "echo-web",
                "namespace": "vibekube-demo",
                "resourceVersion": "10"
              },
              "spec": {
                "replicas": 1
              }
            }
            """
        )
    }

    private func validDeploymentYAML(replicas: Int) -> String {
        """
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: echo-web
          namespace: vibekube-demo
          resourceVersion: "10"
        spec:
          replicas: \(replicas)
        """
    }

    private func resourceDetail(_ json: String) throws -> KubernetesResourceDetail {
        try JSONDecoder().decode(KubernetesResourceDetail.self, from: Data(json.utf8))
    }

    private func kubeconfig() -> Kubeconfig {
        Kubeconfig.empty
    }
}

private actor RecordingMutationService: KubernetesMutationServicing {
    private var requests: [KubernetesMutationRequest] = []
    private let handler: @Sendable (KubernetesMutationRequest) async throws -> KubernetesMutationResult

    init(handler: @escaping @Sendable (KubernetesMutationRequest) async throws -> KubernetesMutationResult) {
        self.handler = handler
    }

    func mutate(
        contextName: String,
        kubeconfig: Kubeconfig,
        request: KubernetesMutationRequest
    ) async throws -> KubernetesMutationResult {
        requests.append(request)
        return try await handler(request)
    }

    func requestCount() -> Int {
        requests.count
    }
}

private struct StaticResourceDetailService: KubernetesResourceDetailServicing {
    var detail: KubernetesResourceDetail

    func resourceDetail(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesResourceDetail {
        detail
    }
}
