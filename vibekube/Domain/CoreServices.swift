import Foundation

enum DefaultNamespaceBehavior: String, CaseIterable, Identifiable {
    case allNamespaces
    case contextNamespace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allNamespaces:
            "All Namespaces"
        case .contextNamespace:
            "Kubeconfig namespace"
        }
    }
}

protocol ClusterRegistry {
    var clusters: [ClusterSummary] { get }
}

protocol ConnectionManaging {
    func connect(to cluster: ClusterSummary) async throws
    func disconnect(from cluster: ClusterSummary)
}

protocol ResourceStoring {
    func refresh() async throws
}

protocol UserPreferencesProviding {
    var selectedContextID: String? { get set }
    var selectedResourceID: String? { get set }
    var selectedNamespaceByContextID: [String: String] { get set }
    var diagnosticsFileLoggingEnabled: Bool { get set }
    var diagnosticsIncludeClusterNames: Bool { get set }
    var diagnosticsRetentionDays: Int { get set }
    var podLogLineLimit: Int { get set }
    var secretRevealRequiresConfirmation: Bool { get set }
    var defaultNamespaceBehavior: DefaultNamespaceBehavior { get set }
}
