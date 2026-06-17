import Foundation

struct PortForwardSession: Identifiable, Equatable {
    enum Status: Equatable {
        case starting
        case running(processIdentifier: Int32?)
        case stopped
        case failed(String)
    }

    var id: UUID
    var contextID: String
    var namespace: String?
    var resourceKind: String
    var resourceName: String
    var portName: String?
    var localPort: Int
    var remotePort: Int
    var startedAt: Date
    var status: Status

    var isActive: Bool {
        switch status {
        case .starting, .running:
            true
        case .stopped, .failed:
            false
        }
    }

    var displayResource: String {
        "\(resourceKind)/\(resourceName)"
    }

    var displayNamespace: String {
        namespace ?? "default"
    }

    var localURLString: String {
        "http://127.0.0.1:\(localPort)"
    }

    func matches(target: KubernetesPortForwardTargetSummary, contextID: String) -> Bool {
        self.contextID == contextID &&
            namespace == target.namespace &&
            resourceKind == target.resourceKind &&
            resourceName == target.resourceName &&
            localPort == target.localPort &&
            remotePort == target.remotePort
    }
}
