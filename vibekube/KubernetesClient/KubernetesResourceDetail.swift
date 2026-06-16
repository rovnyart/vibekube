import Foundation

struct KubernetesResourceDetail: Decodable, Equatable {
    var value: KubernetesJSONValue

    init(from decoder: Decoder) throws {
        self.value = try KubernetesJSONValue(from: decoder)
    }

    nonisolated var kind: String? {
        value["kind"]?.stringValue
    }

    nonisolated var yaml: String {
        KubernetesYAMLRenderer.render(
            value,
            redactedTopLevelKeys: isSecret ? ["binaryData", "data", "stringData"] : []
        )
    }

    nonisolated func decodedSecretValue(forKey key: String) -> String? {
        guard isSecret else {
            return nil
        }

        if let value = value["stringData"]?[key]?.stringValue {
            return value
        }

        guard let encodedValue = value["data"]?[key]?.stringValue,
              let data = Data(base64Encoded: encodedValue) else {
            return nil
        }

        return String(decoding: data, as: UTF8.self)
    }

    nonisolated var summary: KubernetesResourceDetailSummary {
        KubernetesResourceDetailSummary(value: value)
    }

    private nonisolated var isSecret: Bool {
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
    var environment: [KubernetesContainerEnvironmentSummary]

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
        self.environment = Self.environment(in: spec)
    }

    nonisolated private static func statusText(value: KubernetesJSONValue) -> String? {
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

    nonisolated private static func stringMap(
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

    nonisolated private static func shouldRedactMetadataValue(key: String, kind: String?) -> Bool {
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

    nonisolated private static func ownerReferences(in metadata: KubernetesJSONValue?) -> [KubernetesOwnerReferenceSummary] {
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

    nonisolated private static func conditions(in status: KubernetesJSONValue?) -> [KubernetesConditionSummary] {
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

    nonisolated private static func containers(
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

    nonisolated private static func environment(in spec: KubernetesJSONValue?) -> [KubernetesContainerEnvironmentSummary] {
        spec?["containers"]?.arrayValue?.compactMap { value -> KubernetesContainerEnvironmentSummary? in
            guard let object = value.objectValue,
                  let name = object["name"]?.stringValue else {
                return nil
            }

            let variables = object["env"]?.arrayValue?.compactMap(environmentVariable) ?? []
            let envFrom = object["envFrom"]?.arrayValue?.compactMap(environmentFromSource) ?? []

            guard !variables.isEmpty || !envFrom.isEmpty else {
                return nil
            }

            return KubernetesContainerEnvironmentSummary(
                containerName: name,
                variables: variables,
                envFrom: envFrom
            )
        } ?? []
    }

    nonisolated private static func environmentVariable(_ value: KubernetesJSONValue) -> KubernetesEnvVarSummary? {
        guard let object = value.objectValue,
              let name = object["name"]?.stringValue else {
            return nil
        }

        return KubernetesEnvVarSummary(
            name: name,
            literalValue: object["value"]?.stringValue,
            source: environmentVariableSource(object["valueFrom"])
        )
    }

    nonisolated private static func environmentVariableSource(_ value: KubernetesJSONValue?) -> KubernetesEnvVarSourceSummary? {
        guard let value else {
            return nil
        }

        if let object = value["secretKeyRef"]?.objectValue {
            return KubernetesEnvVarSourceSummary(
                kind: .secretKeyRef,
                name: object["name"]?.stringValue,
                key: object["key"]?.stringValue,
                fieldPath: nil,
                resource: nil,
                isOptional: object["optional"]?.boolValue
            )
        }

        if let object = value["configMapKeyRef"]?.objectValue {
            return KubernetesEnvVarSourceSummary(
                kind: .configMapKeyRef,
                name: object["name"]?.stringValue,
                key: object["key"]?.stringValue,
                fieldPath: nil,
                resource: nil,
                isOptional: object["optional"]?.boolValue
            )
        }

        if let object = value["fieldRef"]?.objectValue {
            return KubernetesEnvVarSourceSummary(
                kind: .fieldRef,
                name: nil,
                key: nil,
                fieldPath: object["fieldPath"]?.stringValue,
                resource: nil,
                isOptional: nil
            )
        }

        if let object = value["resourceFieldRef"]?.objectValue {
            return KubernetesEnvVarSourceSummary(
                kind: .resourceFieldRef,
                name: object["containerName"]?.stringValue,
                key: nil,
                fieldPath: nil,
                resource: object["resource"]?.stringValue,
                isOptional: nil
            )
        }

        return KubernetesEnvVarSourceSummary(
            kind: .unknown,
            name: nil,
            key: nil,
            fieldPath: nil,
            resource: nil,
            isOptional: nil
        )
    }

    nonisolated private static func environmentFromSource(_ value: KubernetesJSONValue) -> KubernetesEnvFromSummary? {
        guard let object = value.objectValue else {
            return nil
        }

        if let secretRef = object["secretRef"]?.objectValue,
           let name = secretRef["name"]?.stringValue {
            return KubernetesEnvFromSummary(
                kind: .secretRef,
                name: name,
                prefix: object["prefix"]?.stringValue,
                isOptional: secretRef["optional"]?.boolValue
            )
        }

        if let configMapRef = object["configMapRef"]?.objectValue,
           let name = configMapRef["name"]?.stringValue {
            return KubernetesEnvFromSummary(
                kind: .configMapRef,
                name: name,
                prefix: object["prefix"]?.stringValue,
                isOptional: configMapRef["optional"]?.boolValue
            )
        }

        return nil
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

struct KubernetesContainerEnvironmentSummary: Equatable, Identifiable {
    var containerName: String
    var variables: [KubernetesEnvVarSummary]
    var envFrom: [KubernetesEnvFromSummary]

    var id: String {
        containerName
    }
}

struct KubernetesEnvVarSummary: Equatable, Identifiable {
    var name: String
    var literalValue: String?
    var source: KubernetesEnvVarSourceSummary?

    var id: String {
        [
            name,
            literalValue ?? "",
            source?.id ?? ""
        ].joined(separator: "|")
    }
}

struct KubernetesEnvVarSourceSummary: Equatable {
    var kind: KubernetesEnvVarSourceKind
    var name: String?
    var key: String?
    var fieldPath: String?
    var resource: String?
    var isOptional: Bool?

    var id: String {
        [
            kind.rawValue,
            name ?? "",
            key ?? "",
            fieldPath ?? "",
            resource ?? ""
        ].joined(separator: "|")
    }
}

enum KubernetesEnvVarSourceKind: String, Equatable {
    case secretKeyRef
    case configMapKeyRef
    case fieldRef
    case resourceFieldRef
    case unknown
}

struct KubernetesEnvFromSummary: Equatable, Identifiable {
    var kind: KubernetesEnvFromSourceKind
    var name: String
    var prefix: String?
    var isOptional: Bool?

    var id: String {
        [
            kind.rawValue,
            name,
            prefix ?? ""
        ].joined(separator: "|")
    }
}

enum KubernetesEnvFromSourceKind: String, Equatable {
    case secretRef
    case configMapRef
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
