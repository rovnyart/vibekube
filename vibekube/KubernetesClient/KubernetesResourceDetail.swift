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

    private var isSecret: Bool {
        kind == "Secret"
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

    private static func escapedCharacter(_ character: Character) -> String {
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
