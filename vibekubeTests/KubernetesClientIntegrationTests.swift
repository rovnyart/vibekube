import Foundation
import Testing
@testable import vibekube

struct KubernetesClientIntegrationTests {

    @Test func connectsToCurrentKubeconfigWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["VIBEKUBE_RUN_KIND_INTEGRATION"] == "1" else {
            return
        }

        let result = KubeconfigLoader().load()
        let contextName = try #require(result.kubeconfig.currentContext ?? result.kubeconfig.contexts.first?.name)
        let snapshot = try await KubernetesConnectionService().connect(
            contextName: contextName,
            kubeconfig: result.kubeconfig
        )

        #expect(snapshot.version.gitVersion.hasPrefix("v"))
        #expect(snapshot.discovery.coreVersions.contains("v1"))
        #expect(snapshot.discovery.resourceCount > 0)
        #expect(!snapshot.discovery.namespaceDiscovery.items.isEmpty || snapshot.discovery.namespaceDiscovery.errorMessage != nil)

        let pods = try #require(snapshot.discovery.discoveredResources.first { $0.name == "pods" && $0.group.isEmpty })
        let podList = try await KubernetesResourceListService().listResources(
            contextName: contextName,
            kubeconfig: result.kubeconfig,
            resource: pods,
            namespace: nil
        )
        #expect(podList.items.allSatisfy { $0.displayKind == "Pod" })
    }

    @Test func runsSafeMutationFlowAgainstDisposableKindNamespaceWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["VIBEKUBE_RUN_KIND_INTEGRATION"] == "1" else {
            return
        }

        let result = KubeconfigLoader().load()
        let contextName = try #require(result.kubeconfig.currentContext ?? result.kubeconfig.contexts.first?.name)
        let connection = try await KubernetesConnectionService().connect(
            contextName: contextName,
            kubeconfig: result.kubeconfig
        )

        let namespaceName = "vibekube-it-\(UUID().uuidString.prefix(8).lowercased())"
        let configMapName = "phase10-config"
        let secretName = "phase10-secret"
        let deploymentName = "phase10-worker"

        let namespaces = try discoveredResource(named: "namespaces", groupVersion: "v1", in: connection.discovery)
        let configMaps = try discoveredResource(named: "configmaps", groupVersion: "v1", in: connection.discovery)
        let secrets = try discoveredResource(named: "secrets", groupVersion: "v1", in: connection.discovery)
        let deployments = try discoveredResource(named: "deployments", groupVersion: "apps/v1", in: connection.discovery)
        let mutationService = KubernetesSafeMutationService()
        let detailService = KubernetesResourceDetailService()

        do {
            let namespaceYAML = """
            apiVersion: v1
            kind: Namespace
            metadata:
              name: \(namespaceName)
            """
            _ = try await mutationService.applyManifest(
                contextName: contextName,
                kubeconfig: result.kubeconfig,
                resource: namespaces,
                namespace: nil,
                name: namespaceName,
                yaml: namespaceYAML,
                dryRun: true
            )
            _ = try await mutationService.applyManifest(
                contextName: contextName,
                kubeconfig: result.kubeconfig,
                resource: namespaces,
                namespace: nil,
                name: namespaceName,
                yaml: namespaceYAML,
                dryRun: false
            )

            let configMapYAML = """
            apiVersion: v1
            kind: ConfigMap
            metadata:
              name: \(configMapName)
              namespace: \(namespaceName)
            data:
              PHASE: "10"
              SOURCE: "integration"
            """
            _ = try await mutationService.applyManifest(
                contextName: contextName,
                kubeconfig: result.kubeconfig,
                resource: configMaps,
                namespace: namespaceName,
                name: configMapName,
                yaml: configMapYAML,
                dryRun: true
            )
            let configMap = try await mutationService.applyManifest(
                contextName: contextName,
                kubeconfig: result.kubeconfig,
                resource: configMaps,
                namespace: namespaceName,
                name: configMapName,
                yaml: configMapYAML,
                dryRun: false
            )
            #expect(configMap.yaml.contains("PHASE: \"10\""))

            let secretYAML = """
            apiVersion: v1
            kind: Secret
            metadata:
              name: \(secretName)
              namespace: \(namespaceName)
            type: Opaque
            stringData:
              token: phase10-secret-value
            """
            _ = try await mutationService.applyManifest(
                contextName: contextName,
                kubeconfig: result.kubeconfig,
                resource: secrets,
                namespace: namespaceName,
                name: secretName,
                yaml: secretYAML,
                dryRun: true
            )
            let secret = try await mutationService.applyManifest(
                contextName: contextName,
                kubeconfig: result.kubeconfig,
                resource: secrets,
                namespace: namespaceName,
                name: secretName,
                yaml: secretYAML,
                dryRun: false
            )
            #expect(secret.summary.kind == "Secret")

            let deploymentYAML = """
            apiVersion: apps/v1
            kind: Deployment
            metadata:
              name: \(deploymentName)
              namespace: \(namespaceName)
            spec:
              replicas: 0
              selector:
                matchLabels:
                  app.kubernetes.io/name: \(deploymentName)
              template:
                metadata:
                  labels:
                    app.kubernetes.io/name: \(deploymentName)
                spec:
                  containers:
                    - name: pause
                      image: registry.k8s.io/pause:3.10
            """
            _ = try await mutationService.applyManifest(
                contextName: contextName,
                kubeconfig: result.kubeconfig,
                resource: deployments,
                namespace: namespaceName,
                name: deploymentName,
                yaml: deploymentYAML,
                dryRun: true
            )
            _ = try await mutationService.applyManifest(
                contextName: contextName,
                kubeconfig: result.kubeconfig,
                resource: deployments,
                namespace: namespaceName,
                name: deploymentName,
                yaml: deploymentYAML,
                dryRun: false
            )

            let scaled = try await mutationService.scale(
                contextName: contextName,
                kubeconfig: result.kubeconfig,
                resource: deployments,
                namespace: namespaceName,
                name: deploymentName,
                replicas: 1
            )
            #expect(scaled.yaml.contains("replicas: 1"))

            let restarted = try await mutationService.restartRollout(
                contextName: contextName,
                kubeconfig: result.kubeconfig,
                resource: deployments,
                namespace: namespaceName,
                name: deploymentName,
                restartedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
            #expect(restarted.yaml.contains("kubectl.kubernetes.io/restartedAt"))

            _ = try await mutationService.delete(
                contextName: contextName,
                kubeconfig: result.kubeconfig,
                resource: configMaps,
                namespace: namespaceName,
                name: configMapName
            )
            do {
                _ = try await detailService.resourceDetail(
                    contextName: contextName,
                    kubeconfig: result.kubeconfig,
                    resource: configMaps,
                    namespace: namespaceName,
                    name: configMapName
                )
                Issue.record("Expected deleted ConfigMap lookup to fail")
            } catch {
                #expect(String(describing: error).contains("404") || error.localizedDescription.contains("not found"))
            }

            try await deleteNamespaceIfPresent(
                namespaceName,
                contextName: contextName,
                kubeconfig: result.kubeconfig,
                namespaces: namespaces,
                mutationService: mutationService
            )
        } catch {
            try await deleteNamespaceIfPresent(
                namespaceName,
                contextName: contextName,
                kubeconfig: result.kubeconfig,
                namespaces: namespaces,
                mutationService: mutationService
            )
            throw error
        }
    }
}

private func discoveredResource(
    named name: String,
    groupVersion: String,
    in discovery: KubernetesDiscoverySnapshot
) throws -> KubernetesDiscoveredResource {
    try #require(
        discovery.discoveredResources.first {
            $0.name == name && $0.groupVersion == groupVersion
        }
    )
}

private func deleteNamespaceIfPresent(
    _ name: String,
    contextName: String,
    kubeconfig: Kubeconfig,
    namespaces: KubernetesDiscoveredResource,
    mutationService: KubernetesSafeMutationServicing
) async throws {
    do {
        _ = try await mutationService.delete(
            contextName: contextName,
            kubeconfig: kubeconfig,
            resource: namespaces,
            namespace: nil,
            name: name
        )
    } catch {
        if !String(describing: error).contains("404") &&
            !error.localizedDescription.localizedCaseInsensitiveContains("not found") {
            throw error
        }
    }
}
