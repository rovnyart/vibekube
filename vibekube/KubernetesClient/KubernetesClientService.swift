import Foundation

protocol KubernetesClientService {
    func refreshDiscovery() async throws
}
