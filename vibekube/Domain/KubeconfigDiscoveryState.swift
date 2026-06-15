import Foundation

enum KubeconfigDiscoveryState: Equatable {
    case notLoaded
    case loaded(contextCount: Int, sourceCount: Int)
    case missing(paths: [String])
    case failed(message: String)

    var title: String {
        switch self {
        case .notLoaded:
            "Not Loaded"
        case .loaded(let contextCount, let sourceCount):
            "\(contextCount) context\(contextCount == 1 ? "" : "s") from \(sourceCount) source\(sourceCount == 1 ? "" : "s")"
        case .missing:
            "No kubeconfig found"
        case .failed:
            "Could not load kubeconfig"
        }
    }

    var detail: String {
        switch self {
        case .notLoaded:
            "Waiting to discover local clusters."
        case .loaded:
            "Select a context to continue."
        case .missing(let paths):
            "Checked \(paths.joined(separator: ", "))."
        case .failed(let message):
            message
        }
    }
}
