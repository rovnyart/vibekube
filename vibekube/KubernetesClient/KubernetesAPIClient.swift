import Foundation

protocol KubernetesAPIClient {
    func version() async throws -> KubernetesVersion
    func apiVersions() async throws -> KubernetesAPIVersions
    func apiGroups() async throws -> KubernetesAPIGroupList
    func resources(groupVersion: String) async throws -> KubernetesAPIResourceList
    func namespaces() async throws -> KubernetesNamespaceList
    func resourceList(
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList
    func resourceDetail(
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesResourceDetail
    func resourceEvents(
        eventsResource: KubernetesDiscoveredResource,
        namespace: String?,
        involvedKind: String,
        involvedName: String,
        involvedUID: String?
    ) async throws -> KubernetesResourceEventList
    func nodeMetrics() async throws -> KubernetesNodeMetricsList
    func podMetrics(namespace: String?) async throws -> KubernetesPodMetricsList
    func podLogs(
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) async throws -> String
    func podLogStream(
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) -> AsyncThrowingStream<String, Error>
}

struct KubernetesVersion: Decodable, Equatable {
    var major: String
    var minor: String
    var gitVersion: String
    var gitCommit: String?
    var platform: String?
}

struct KubernetesStatus: Decodable, Equatable {
    var kind: String?
    var apiVersion: String?
    var status: String?
    var message: String?
    var reason: String?
    var code: Int?
}
