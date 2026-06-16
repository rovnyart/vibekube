import Foundation

struct KubernetesPodLogOptions: Equatable {
    var container: String?
    var previous: Bool
    var follow: Bool
    var tailLines: Int?
    var sinceSeconds: Int?
    var timestamps: Bool

    init(
        container: String? = nil,
        previous: Bool = false,
        follow: Bool = false,
        tailLines: Int? = nil,
        sinceSeconds: Int? = nil,
        timestamps: Bool = false
    ) {
        self.container = container
        self.previous = previous
        self.follow = follow
        self.tailLines = tailLines
        self.sinceSeconds = sinceSeconds
        self.timestamps = timestamps
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []

        if let container, !container.isEmpty {
            items.append(URLQueryItem(name: "container", value: container))
        }

        if previous {
            items.append(URLQueryItem(name: "previous", value: "true"))
        }

        if follow {
            items.append(URLQueryItem(name: "follow", value: "true"))
        }

        if let tailLines {
            items.append(URLQueryItem(name: "tailLines", value: "\(tailLines)"))
        }

        if let sinceSeconds {
            items.append(URLQueryItem(name: "sinceSeconds", value: "\(sinceSeconds)"))
        }

        if timestamps {
            items.append(URLQueryItem(name: "timestamps", value: "true"))
        }

        return items
    }
}
