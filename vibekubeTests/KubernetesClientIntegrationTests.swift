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
    }
}
