import Foundation

enum KubernetesWatchEventType: String, Decodable, Equatable {
    case added = "ADDED"
    case modified = "MODIFIED"
    case deleted = "DELETED"
    case bookmark = "BOOKMARK"
    case error = "ERROR"
}

struct KubernetesWatchEvent<Resource: Decodable & Equatable>: Decodable, Equatable {
    var type: KubernetesWatchEventType
    var object: Resource?
    var status: KubernetesStatus?

    private enum CodingKeys: String, CodingKey {
        case type
        case object
    }

    init(type: KubernetesWatchEventType, object: Resource?, status: KubernetesStatus? = nil) {
        self.type = type
        self.object = object
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(KubernetesWatchEventType.self, forKey: .type)

        if type == .error {
            status = try? container.decode(KubernetesStatus.self, forKey: .object)
            object = nil
        } else {
            object = try? container.decode(Resource.self, forKey: .object)
            status = nil
        }
    }
}
