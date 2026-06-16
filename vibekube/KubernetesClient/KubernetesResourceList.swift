import Foundation

struct KubernetesUnstructuredResourceList: Decodable, Equatable {
    var apiVersion: String?
    var kind: String?
    var metadata: KubernetesListMetadata?
    var items: [KubernetesUnstructuredResource]

    static func merged(_ lists: [KubernetesUnstructuredResourceList]) -> KubernetesUnstructuredResourceList {
        KubernetesUnstructuredResourceList(
            apiVersion: lists.last?.apiVersion ?? lists.first?.apiVersion,
            kind: lists.last?.kind ?? lists.first?.kind,
            metadata: lists.last?.metadata,
            items: lists.flatMap(\.items)
        )
    }
}

struct KubernetesListMetadata: Decodable, Equatable {
    var resourceVersion: String?
    var continueToken: String?
    var remainingItemCount: Int?

    private enum CodingKeys: String, CodingKey {
        case resourceVersion
        case continueToken = "continue"
        case remainingItemCount
    }
}

struct KubernetesUnstructuredResource: Decodable, Identifiable, Equatable, Hashable {
    var apiVersion: String?
    var kind: String?
    var metadata: KubernetesObjectMetadata
    var spec: KubernetesJSONValue?
    var status: KubernetesJSONValue?
    var reason: String?
    var type: String?
    var message: String?
    var note: String?
    var count: Int?
    var eventTime: String?
    var firstTimestamp: String?
    var lastTimestamp: String?
    var deprecatedFirstTimestamp: String?
    var deprecatedLastTimestamp: String?
    var deprecatedCount: Int?
    var reportingComponent: String?
    var reportingController: String?
    var reportingInstance: String?
    var source: KubernetesJSONValue?
    var deprecatedSource: KubernetesJSONValue?
    var regarding: KubernetesJSONValue?
    var involvedObject: KubernetesJSONValue?
    var series: KubernetesJSONValue?

    var id: String {
        metadata.uid ?? "\(displayKind)/\(displayNamespace)/\(displayName)"
    }

    var displayName: String {
        metadata.name ?? "Unknown"
    }

    var displayNamespace: String {
        metadata.namespace ?? "-"
    }

    var displayKind: String {
        kind ?? "Unknown"
    }

    var displayStatus: String {
        if isEvent {
            if let type, let reason {
                return "\(type) \(reason)"
            }
            return reason ?? type ?? "-"
        }

        if let deletionTimestamp = metadata.deletionTimestamp, !deletionTimestamp.isEmpty {
            return "Terminating"
        }

        if let phase = status?["phase"]?.stringValue, !phase.isEmpty {
            return phase
        }

        if let ready = readyReplicas, let desired = desiredReplicas {
            return "\(ready)/\(desired) ready"
        }

        if let ready = readyReplicas {
            return "\(ready) ready"
        }

        return type ?? "-"
    }

    var labelsSummary: String {
        guard let labels = metadata.labels, !labels.isEmpty else {
            return "-"
        }

        return labels
            .sorted { lhs, rhs in lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending }
            .prefix(3)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }

    var searchBlob: String {
        [
            displayName,
            displayNamespace,
            displayKind,
            displayStatus,
            labelsSummary,
            reason,
            type,
            eventMessage,
            eventSourceDescription,
            eventInvolvedObjectDescription
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }

    func ageDescription(now: Date = Date()) -> String {
        guard let creationDate else {
            return "-"
        }

        let seconds = max(0, Int(now.timeIntervalSince(creationDate)))
        switch seconds {
        case ..<60:
            return "\(seconds)s"
        case ..<3_600:
            return "\(seconds / 60)m"
        case ..<86_400:
            return "\(seconds / 3_600)h"
        default:
            return "\(seconds / 86_400)d"
        }
    }

    var creationDate: Date? {
        guard let creationTimestamp = metadata.creationTimestamp else {
            return nil
        }

        return Self.iso8601Date(from: creationTimestamp)
    }

    var eventMessage: String? {
        note ?? message
    }

    var eventCount: Int? {
        series?["count"]?.intValue ?? deprecatedCount ?? count
    }

    var eventLastObservedDate: Date? {
        [
            series?["lastObservedTime"]?.stringValue,
            deprecatedLastTimestamp,
            lastTimestamp,
            eventTime,
            metadata.creationTimestamp
        ]
        .compactMap { $0 }
        .compactMap(Self.iso8601Date(from:))
        .first
    }

    var eventSourceDescription: String? {
        let controller = reportingController ??
            reportingComponent ??
            source?["component"]?.stringValue ??
            deprecatedSource?["component"]?.stringValue
        let instance = reportingInstance ??
            source?["host"]?.stringValue ??
            deprecatedSource?["host"]?.stringValue

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

    var eventInvolvedObjectDescription: String? {
        let object = regarding ?? involvedObject
        let parts = [
            object?["kind"]?.stringValue,
            object?["namespace"]?.stringValue,
            object?["name"]?.stringValue
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        }

        let objectText = parts.joined(separator: " / ")
        if let fieldPath = object?["fieldPath"]?.stringValue, !fieldPath.isEmpty {
            return objectText.isEmpty ? fieldPath : "\(objectText) / \(fieldPath)"
        }

        return objectText.isEmpty ? nil : objectText
    }

    func eventAgeDescription(now: Date = Date()) -> String {
        guard let eventLastObservedDate else {
            return "-"
        }

        let seconds = max(0, Int(now.timeIntervalSince(eventLastObservedDate)))
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

    private static func iso8601Date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private var isEvent: Bool {
        displayKind == "Event" || reason != nil && (message != nil || note != nil)
    }

    private var desiredReplicas: Int? {
        spec?["replicas"]?.intValue ??
            status?["desiredNumberScheduled"]?.intValue ??
            status?["replicas"]?.intValue
    }

    private var readyReplicas: Int? {
        status?["readyReplicas"]?.intValue ??
            status?["availableReplicas"]?.intValue ??
            status?["numberReady"]?.intValue
    }
}

enum KubernetesJSONValue: Decodable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: KubernetesJSONValue])
    case array([KubernetesJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let object = try? container.decode([String: KubernetesJSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([KubernetesJSONValue].self) {
            self = .array(array)
        } else {
            self = .null
        }
    }

    subscript(key: String) -> KubernetesJSONValue? {
        guard case .object(let object) = self else {
            return nil
        }
        return object[key]
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .number(let value):
            return Int(value)
        case .string(let value):
            return Int(value)
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            value
        case .string(let value):
            Bool(value)
        default:
            nil
        }
    }

    var objectValue: [String: KubernetesJSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    var arrayValue: [KubernetesJSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    var displayValue: String {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            if value.rounded() == value {
                String(Int(value))
            } else {
                String(value)
            }
        case .bool(let value):
            value ? "true" : "false"
        case .null:
            "null"
        case .object, .array:
            "-"
        }
    }
}
