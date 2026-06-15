import Foundation

struct KubernetesResourceEventList: Decodable, Equatable {
    var apiVersion: String?
    var kind: String?
    var metadata: KubernetesListMetadata?
    var items: [KubernetesResourceEvent]

    var summaries: [KubernetesResourceEventSummary] {
        items
            .map(\.summary)
            .sorted { lhs, rhs in
                switch (lhs.lastObservedAt, rhs.lastObservedAt) {
                case (.some(let lhsDate), .some(let rhsDate)):
                    lhsDate > rhsDate
                case (.some, .none):
                    true
                case (.none, .some):
                    false
                case (.none, .none):
                    lhs.reason.localizedStandardCompare(rhs.reason) == .orderedAscending
                }
            }
    }
}

struct KubernetesResourceEvent: Decodable, Equatable {
    var value: KubernetesJSONValue

    init(from decoder: Decoder) throws {
        self.value = try KubernetesJSONValue(from: decoder)
    }

    var summary: KubernetesResourceEventSummary {
        KubernetesResourceEventSummary(value: value)
    }
}

struct KubernetesResourceEventSummary: Equatable, Identifiable {
    var id: String
    var name: String
    var namespace: String?
    var type: String
    var reason: String
    var message: String
    var count: Int?
    var source: String?
    var involvedKind: String?
    var involvedName: String?
    var involvedNamespace: String?
    var involvedFieldPath: String?
    var firstObserved: String?
    var lastObserved: String?
    var lastObservedAt: Date?

    init(value: KubernetesJSONValue) {
        let metadata = value["metadata"]
        let regarding = value["regarding"] ?? value["involvedObject"]
        let name = metadata?["name"]?.stringValue ?? "-"
        let namespace = metadata?["namespace"]?.stringValue
        let message = value["note"]?.stringValue ??
            value["message"]?.stringValue ??
            "-"
        let firstObserved = value["deprecatedFirstTimestamp"]?.stringValue ??
            value["firstTimestamp"]?.stringValue
        let lastObserved = value["series"]?["lastObservedTime"]?.stringValue ??
            value["deprecatedLastTimestamp"]?.stringValue ??
            value["lastTimestamp"]?.stringValue ??
            value["eventTime"]?.stringValue ??
            metadata?["creationTimestamp"]?.stringValue

        self.id = metadata?["uid"]?.stringValue ?? [
            name,
            value["reason"]?.stringValue ?? "",
            lastObserved ?? ""
        ].joined(separator: "|")
        self.name = name
        self.namespace = namespace
        self.type = value["type"]?.stringValue ?? "-"
        self.reason = value["reason"]?.stringValue ?? "-"
        self.message = message
        self.count = value["series"]?["count"]?.intValue ??
            value["deprecatedCount"]?.intValue ??
            value["count"]?.intValue
        self.source = Self.source(in: value)
        self.involvedKind = regarding?["kind"]?.stringValue
        self.involvedName = regarding?["name"]?.stringValue
        self.involvedNamespace = regarding?["namespace"]?.stringValue
        self.involvedFieldPath = regarding?["fieldPath"]?.stringValue
        self.firstObserved = firstObserved
        self.lastObserved = lastObserved
        self.lastObservedAt = lastObserved.flatMap(Self.date(from:))
    }

    func ageDescription(now: Date = Date()) -> String {
        guard let lastObservedAt else {
            return lastObserved ?? "-"
        }

        let seconds = max(0, Int(now.timeIntervalSince(lastObservedAt)))
        switch seconds {
        case ..<60:
            return "\(seconds)s ago"
        case ..<3_600:
            return "\(seconds / 60)m ago"
        case ..<86_400:
            return "\(seconds / 3_600)h ago"
        default:
            return "\(seconds / 86_400)d ago"
        }
    }

    private static func source(in value: KubernetesJSONValue) -> String? {
        let controller = value["reportingController"]?.stringValue ??
            value["reportingComponent"]?.stringValue ??
            value["source"]?["component"]?.stringValue ??
            value["deprecatedSource"]?["component"]?.stringValue
        let instance = value["reportingInstance"]?.stringValue ??
            value["source"]?["host"]?.stringValue ??
            value["deprecatedSource"]?["host"]?.stringValue

        switch (controller, instance) {
        case (.some(let controller), .some(let instance)) where !instance.isEmpty:
            return "\(controller) / \(instance)"
        case (.some(let controller), _):
            return controller
        case (_, .some(let instance)) where !instance.isEmpty:
            return instance
        default:
            return nil
        }
    }

    private static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

protocol KubernetesResourceEventServicing {
    func resourceEvents(
        contextName: String,
        kubeconfig: Kubeconfig,
        eventsResource: KubernetesDiscoveredResource,
        namespace: String?,
        involvedKind: String,
        involvedName: String,
        involvedUID: String?
    ) async throws -> KubernetesResourceEventList
}

final class KubernetesResourceEventService: KubernetesResourceEventServicing {
    private let execCredentialProvider: KubernetesExecCredentialProviding

    init(execCredentialProvider: KubernetesExecCredentialProviding = DefaultKubernetesExecCredentialProvider()) {
        self.execCredentialProvider = execCredentialProvider
    }

    func resourceEvents(
        contextName: String,
        kubeconfig: Kubeconfig,
        eventsResource: KubernetesDiscoveredResource,
        namespace: String?,
        involvedKind: String,
        involvedName: String,
        involvedUID: String?
    ) async throws -> KubernetesResourceEventList {
        var configuration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
        let execRequest = try await resolveExecCredentialIfNeeded(configuration: &configuration)
        let client = try DefaultKubernetesAPIClient(configuration: configuration)

        do {
            return try await client.resourceEvents(
                eventsResource: eventsResource,
                namespace: namespace,
                involvedKind: involvedKind,
                involvedName: involvedName,
                involvedUID: involvedUID
            )
        } catch let error as KubernetesClientError where error.connectionState == .unauthorized {
            guard let execRequest else {
                throw error
            }

            execCredentialProvider.invalidate(execRequest)
            var retryConfiguration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
            _ = try await resolveExecCredentialIfNeeded(configuration: &retryConfiguration)
            let retryClient = try DefaultKubernetesAPIClient(configuration: retryConfiguration)
            return try await retryClient.resourceEvents(
                eventsResource: eventsResource,
                namespace: namespace,
                involvedKind: involvedKind,
                involvedName: involvedName,
                involvedUID: involvedUID
            )
        }
    }

    private func resolveExecCredentialIfNeeded(
        configuration: inout KubernetesClientConfiguration
    ) async throws -> KubernetesExecCredentialRequest? {
        guard case .exec(let request) = configuration.credential else {
            return nil
        }

        configuration.credential = try await execCredentialProvider.credential(for: request)
        return request
    }
}
