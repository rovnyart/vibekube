import Foundation

struct PodLogQuery: Identifiable, Hashable {
    var contextID: ClusterSummary.ID
    var namespace: String
    var podName: String
    var containerName: String?
    var previous: Bool
    var tailLines: Int?
    var timestamps: Bool
    var follow: Bool

    var id: String {
        [
            contextID,
            namespace,
            podName,
            containerName ?? "",
            previous ? "previous" : "current",
            tailLines.map(String.init) ?? "all",
            timestamps ? "timestamps" : "plain",
            follow ? "follow" : "tail"
        ].joined(separator: "|")
    }

    var title: String {
        if let containerName, !containerName.isEmpty {
            return "\(podName) / \(containerName)"
        }

        return podName
    }
}

struct PodLogSnapshot: Equatable {
    var query: PodLogQuery
    var text: String
    var loadedAt: Date

    var lines: [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}

enum PodLogLoadState: Equatable {
    case idle
    case loading
    case loaded(PodLogSnapshot)
    case failed(String)
}
