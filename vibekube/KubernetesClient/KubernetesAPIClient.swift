import Foundation

protocol KubernetesAPIClient {
    func version() async throws -> KubernetesVersion
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
