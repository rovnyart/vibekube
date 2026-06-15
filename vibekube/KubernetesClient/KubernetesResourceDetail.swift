import Foundation

struct KubernetesResourceDetail: Decodable, Equatable {
    var value: KubernetesJSONValue

    init(from decoder: Decoder) throws {
        self.value = try KubernetesJSONValue(from: decoder)
    }

    var kind: String? {
        value["kind"]?.stringValue
    }

    var yaml: String {
        KubernetesYAMLRenderer.render(
            value,
            redactedTopLevelKeys: isSecret ? ["binaryData", "data", "stringData"] : []
        )
    }

    var summary: KubernetesResourceDetailSummary {
        KubernetesResourceDetailSummary(value: value)
    }

    private var isSecret: Bool {
        kind == "Secret"
    }
}

struct KubernetesResourceDetailSummary: Equatable {
    var apiVersion: String?
    var kind: String?
    var name: String?
    var namespace: String?
    var uid: String?
    var resourceVersion: String?
    var creationTimestamp: String?
    var deletionTimestamp: String?
    var status: String?
    var type: String?
    var labels: [String: String]
    var annotations: [String: String]
    var ownerReferences: [KubernetesOwnerReferenceSummary]
    var conditions: [KubernetesConditionSummary]
    var containers: [KubernetesContainerSummary]

    init(value: KubernetesJSONValue) {
        let metadata = value["metadata"]
        let spec = value["spec"]
        let statusObject = value["status"]
        let kind = value["kind"]?.stringValue

        self.apiVersion = value["apiVersion"]?.stringValue
        self.kind = kind
        self.name = metadata?["name"]?.stringValue
        self.namespace = metadata?["namespace"]?.stringValue
        self.uid = metadata?["uid"]?.stringValue
        self.resourceVersion = metadata?["resourceVersion"]?.stringValue
        self.creationTimestamp = metadata?["creationTimestamp"]?.stringValue
        self.deletionTimestamp = metadata?["deletionTimestamp"]?.stringValue
        self.status = Self.statusText(value: value)
        self.type = value["type"]?.stringValue
        self.labels = Self.stringMap(metadata?["labels"], redactingValues: false, kind: kind)
        self.annotations = Self.stringMap(metadata?["annotations"], redactingValues: true, kind: kind)
        self.ownerReferences = Self.ownerReferences(in: metadata)
        self.conditions = Self.conditions(in: statusObject)
        self.containers = Self.containers(in: spec, status: statusObject)
    }

    private static func statusText(value: KubernetesJSONValue) -> String? {
        if let phase = value["status"]?["phase"]?.stringValue, !phase.isEmpty {
            return phase
        }

        if let reason = value["reason"]?.stringValue, !reason.isEmpty {
            return reason
        }

        if let type = value["type"]?.stringValue, !type.isEmpty {
            return type
        }

        let readyReplicas = value["status"]?["readyReplicas"]?.intValue ??
            value["status"]?["availableReplicas"]?.intValue ??
            value["status"]?["numberReady"]?.intValue
        let desiredReplicas = value["spec"]?["replicas"]?.intValue ??
            value["status"]?["desiredNumberScheduled"]?.intValue ??
            value["status"]?["replicas"]?.intValue

        if let readyReplicas, let desiredReplicas {
            return "\(readyReplicas)/\(desiredReplicas) ready"
        }

        return nil
    }

    private static func stringMap(
        _ value: KubernetesJSONValue?,
        redactingValues: Bool,
        kind: String?
    ) -> [String: String] {
        guard let object = value?.objectValue else {
            return [:]
        }

        var result: [String: String] = [:]
        for (key, value) in object {
            let displayValue = value.displayValue
            result[key] = redactingValues && shouldRedactMetadataValue(key: key, kind: kind)
                ? "<redacted>"
                : displayValue
        }
        return result
    }

    private static func shouldRedactMetadataValue(key: String, kind: String?) -> Bool {
        if kind == "Secret" {
            return true
        }

        let sensitiveFragments = [
            "authorization",
            "client-key",
            "credential",
            "kubeconfig",
            "last-applied-configuration",
            "password",
            "secret",
            "token"
        ]
        let lowercasedKey = key.lowercased()
        return sensitiveFragments.contains { lowercasedKey.contains($0) }
    }

    private static func ownerReferences(in metadata: KubernetesJSONValue?) -> [KubernetesOwnerReferenceSummary] {
        metadata?["ownerReferences"]?.arrayValue?.compactMap { value in
            guard let object = value.objectValue else {
                return nil
            }

            return KubernetesOwnerReferenceSummary(
                kind: object["kind"]?.stringValue ?? "-",
                name: object["name"]?.stringValue ?? "-",
                controller: object["controller"]?.boolValue ?? false
            )
        } ?? []
    }

    private static func conditions(in status: KubernetesJSONValue?) -> [KubernetesConditionSummary] {
        status?["conditions"]?.arrayValue?.compactMap { value in
            guard let object = value.objectValue else {
                return nil
            }

            return KubernetesConditionSummary(
                type: object["type"]?.stringValue ?? "-",
                status: object["status"]?.stringValue ?? "-",
                reason: object["reason"]?.stringValue,
                message: object["message"]?.stringValue,
                lastTransitionTime: object["lastTransitionTime"]?.stringValue ??
                    object["lastUpdateTime"]?.stringValue
            )
        } ?? []
    }

    private static func containers(
        in spec: KubernetesJSONValue?,
        status: KubernetesJSONValue?
    ) -> [KubernetesContainerSummary] {
        let containerStatuses = status?["containerStatuses"]?.arrayValue ?? []
        let statusPairs: [(String, [String: KubernetesJSONValue])] = containerStatuses.compactMap { value in
            guard let object = value.objectValue,
                  let name = object["name"]?.stringValue else {
                return nil
            }
            return (name, object)
        }
        let statusByName: [String: [String: KubernetesJSONValue]] = Dictionary(uniqueKeysWithValues: statusPairs)

        return spec?["containers"]?.arrayValue?.compactMap { value -> KubernetesContainerSummary? in
            guard let object = value.objectValue,
                  let name = object["name"]?.stringValue else {
                return nil
            }

            let status = statusByName[name]
            return KubernetesContainerSummary(
                name: name,
                image: object["image"]?.stringValue,
                ready: status?["ready"]?.boolValue,
                restartCount: status?["restartCount"]?.intValue
            )
        } ?? []
    }
}

struct KubernetesOwnerReferenceSummary: Equatable, Identifiable {
    var kind: String
    var name: String
    var controller: Bool

    var id: String {
        "\(kind)/\(name)"
    }
}

struct KubernetesConditionSummary: Equatable, Identifiable {
    var type: String
    var status: String
    var reason: String?
    var message: String?
    var lastTransitionTime: String?

    var id: String {
        "\(type)/\(status)/\(reason ?? "")/\(lastTransitionTime ?? "")"
    }
}

struct KubernetesContainerSummary: Equatable, Identifiable {
    var name: String
    var image: String?
    var ready: Bool?
    var restartCount: Int?

    var id: String {
        name
    }
}

enum KubernetesYAMLRenderer {
    static func render(
        _ value: KubernetesJSONValue,
        redactedTopLevelKeys: Set<String> = []
    ) -> String {
        renderLines(
            value,
            indent: 0,
            path: [],
            redactedTopLevelKeys: redactedTopLevelKeys
        )
        .joined(separator: "\n") + "\n"
    }

    private static func renderLines(
        _ value: KubernetesJSONValue,
        indent: Int,
        path: [String],
        redactedTopLevelKeys: Set<String>
    ) -> [String] {
        switch value {
        case .object(let object):
            return renderObject(
                object,
                indent: indent,
                path: path,
                redactedTopLevelKeys: redactedTopLevelKeys
            )
        case .array(let array):
            return renderArray(
                array,
                indent: indent,
                path: path,
                redactedTopLevelKeys: redactedTopLevelKeys
            )
        case .string, .number, .bool, .null:
            return ["\(indentation(indent))\(scalar(value))"]
        }
    }

    private static func renderObject(
        _ object: [String: KubernetesJSONValue],
        indent: Int,
        path: [String],
        redactedTopLevelKeys: Set<String>
    ) -> [String] {
        guard !object.isEmpty else {
            return ["\(indentation(indent)){}"]
        }

        var lines: [String] = []
        for key in orderedKeys(for: object) {
            guard let value = object[key] else {
                continue
            }

            let keyText = escapedKey(key)
            if path.isEmpty, redactedTopLevelKeys.contains(key) {
                lines.append("\(indentation(indent))\(keyText): <redacted>")
                continue
            }

            if isScalar(value) {
                lines.append("\(indentation(indent))\(keyText): \(scalar(value))")
            } else {
                lines.append("\(indentation(indent))\(keyText):")
                lines += renderLines(
                    value,
                    indent: indent + 2,
                    path: path + [key],
                    redactedTopLevelKeys: redactedTopLevelKeys
                )
            }
        }

        return lines
    }

    private static func renderArray(
        _ array: [KubernetesJSONValue],
        indent: Int,
        path: [String],
        redactedTopLevelKeys: Set<String>
    ) -> [String] {
        guard !array.isEmpty else {
            return ["\(indentation(indent))[]"]
        }

        return array.flatMap { value -> [String] in
            if isScalar(value) {
                return ["\(indentation(indent))- \(scalar(value))"]
            }

            return ["\(indentation(indent))-"] + renderLines(
                value,
                indent: indent + 2,
                path: path,
                redactedTopLevelKeys: redactedTopLevelKeys
            )
        }
    }

    private static func orderedKeys(for object: [String: KubernetesJSONValue]) -> [String] {
        let preferred = [
            "apiVersion",
            "kind",
            "metadata",
            "spec",
            "status",
            "data",
            "stringData",
            "binaryData"
        ]
        let preferredKeys = preferred.filter { object[$0] != nil }
        let remainingKeys = object.keys
            .filter { !preferred.contains($0) }
            .sorted { lhs, rhs in lhs.localizedStandardCompare(rhs) == .orderedAscending }
        return preferredKeys + remainingKeys
    }

    private static func isScalar(_ value: KubernetesJSONValue) -> Bool {
        switch value {
        case .string, .number, .bool, .null:
            true
        case .object, .array:
            false
        }
    }

    private static func scalar(_ value: KubernetesJSONValue) -> String {
        switch value {
        case .string(let value):
            yamlString(value)
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
            ""
        }
    }

    private static func yamlString(_ value: String) -> String {
        guard !value.isEmpty else {
            return "\"\""
        }

        let reserved = ["false", "null", "true", "~"]
        let simplePattern = #"^[A-Za-z0-9_./:@-]+$"#
        let isSimple = value.range(of: simplePattern, options: .regularExpression) != nil
        if isSimple, !reserved.contains(value.lowercased()) {
            return value
        }

        return "\"\(value.map(escapedCharacter).joined())\""
    }

    private static func escapedKey(_ key: String) -> String {
        yamlString(key)
    }

    nonisolated private static func escapedCharacter(_ character: Character) -> String {
        switch character {
        case "\\":
            "\\\\"
        case "\"":
            "\\\""
        case "\n":
            "\\n"
        case "\r":
            "\\r"
        case "\t":
            "\\t"
        default:
            String(character)
        }
    }

    private static func indentation(_ width: Int) -> String {
        String(repeating: " ", count: width)
    }
}
