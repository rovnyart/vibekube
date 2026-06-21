import Foundation

enum ResourceDetailPanel: String, CaseIterable, Identifiable {
    case overview
    case events
    case logs
    case containers
    case environment
    case yaml
    case metadata
    case conditions

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .overview:
            "Overview"
        case .events:
            "Events"
        case .logs:
            "Logs"
        case .containers:
            "Containers"
        case .environment:
            "Env"
        case .yaml:
            "YAML"
        case .metadata:
            "Metadata"
        case .conditions:
            "Conditions"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "list.bullet.rectangle"
        case .events:
            "waveform.path.ecg"
        case .logs:
            "terminal"
        case .containers:
            "shippingbox"
        case .environment:
            "switch.2"
        case .yaml:
            "doc.plaintext"
        case .metadata:
            "tag"
        case .conditions:
            "checklist"
        }
    }
}
