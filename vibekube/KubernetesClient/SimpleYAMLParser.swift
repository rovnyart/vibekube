import Foundation

enum SimpleYAMLValue: Equatable {
    case mapping([String: SimpleYAMLValue])
    case sequence([SimpleYAMLValue])
    case scalar(String)
    case null

    var mapping: [String: SimpleYAMLValue]? {
        if case .mapping(let value) = self { value } else { nil }
    }

    var sequence: [SimpleYAMLValue]? {
        if case .sequence(let value) = self { value } else { nil }
    }

    var string: String? {
        switch self {
        case .scalar(let value):
            value
        case .null:
            nil
        case .mapping, .sequence:
            nil
        }
    }

    var bool: Bool? {
        guard let string else { return nil }
        switch string.lowercased() {
        case "true", "yes":
            return true
        case "false", "no":
            return false
        default:
            return nil
        }
    }
}

struct SimpleYAMLParser {
    private struct Line {
        var indent: Int
        var content: String
        var number: Int
    }

    private var lines: [Line] = []
    private var index = 0

    mutating func parse(_ rawYAML: String) throws -> SimpleYAMLValue {
        lines = preprocess(rawYAML)
        index = 0

        guard !lines.isEmpty else {
            return .mapping([:])
        }

        return try parseBlock(indent: lines[0].indent)
    }

    private mutating func parseBlock(indent: Int) throws -> SimpleYAMLValue {
        guard index < lines.count else {
            return .null
        }

        if lines[index].content.hasPrefix("-") {
            return try parseSequence(indent: indent)
        }

        return try parseMapping(indent: indent)
    }

    private mutating func parseMapping(indent: Int) throws -> SimpleYAMLValue {
        var mapping: [String: SimpleYAMLValue] = [:]

        while index < lines.count {
            let line = lines[index]
            if line.indent < indent { break }
            if line.indent > indent {
                throw KubeconfigParserError.malformedYAML("unexpected indentation on line \(line.number)")
            }
            if line.content.hasPrefix("-") { break }

            guard let keyValue = parseKeyValue(line.content) else {
                throw KubeconfigParserError.malformedYAML("expected key/value on line \(line.number)")
            }

            index += 1

            if keyValue.value.isEmpty {
                if canParseNestedValue(afterParentIndent: indent) {
                    mapping[keyValue.key] = try parseBlock(indent: lines[index].indent)
                } else {
                    mapping[keyValue.key] = .null
                }
            } else {
                mapping[keyValue.key] = parseScalar(keyValue.value)
            }
        }

        return .mapping(mapping)
    }

    private mutating func parseSequence(indent: Int) throws -> SimpleYAMLValue {
        var values: [SimpleYAMLValue] = []

        while index < lines.count {
            let line = lines[index]
            if line.indent < indent { break }
            if line.indent > indent {
                throw KubeconfigParserError.malformedYAML("unexpected indentation on line \(line.number)")
            }
            guard line.content.hasPrefix("-") else { break }

            let itemContent = line.content.dropFirst().trimmingCharacters(in: .whitespaces)
            index += 1

            if itemContent.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    values.append(try parseBlock(indent: lines[index].indent))
                } else {
                    values.append(.null)
                }
                continue
            }

            if let keyValue = parseKeyValue(itemContent) {
                var item: [String: SimpleYAMLValue] = [:]
                if keyValue.value.isEmpty {
                    if index < lines.count, lines[index].indent > indent {
                        item[keyValue.key] = try parseBlock(indent: lines[index].indent)
                    } else {
                        item[keyValue.key] = .null
                    }
                } else {
                    item[keyValue.key] = parseScalar(keyValue.value)
                }

                if index < lines.count, lines[index].indent > indent {
                    let continuation = try parseBlock(indent: lines[index].indent)
                    if let continuationMapping = continuation.mapping {
                        item.merge(continuationMapping) { _, new in new }
                    }
                }

                values.append(.mapping(item))
            } else {
                values.append(parseScalar(itemContent))
            }
        }

        return .sequence(values)
    }

    private func canParseNestedValue(afterParentIndent indent: Int) -> Bool {
        guard index < lines.count else { return false }

        let next = lines[index]
        return next.indent > indent || (next.indent == indent && next.content.hasPrefix("-"))
    }

    private func preprocess(_ rawYAML: String) -> [Line] {
        rawYAML
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { offset, rawLine in
                let line = String(rawLine)
                let withoutComment = stripComment(from: line).trimmingTrailingWhitespace()
                guard !withoutComment.trimmingCharacters(in: .whitespaces).isEmpty else {
                    return nil
                }

                let indent = withoutComment.prefix(while: { $0 == " " }).count
                let content = withoutComment.trimmingCharacters(in: .whitespaces)
                return Line(indent: indent, content: content, number: offset + 1)
            }
    }

    private func parseKeyValue(_ content: String) -> (key: String, value: String)? {
        var isInSingleQuote = false
        var isInDoubleQuote = false

        for index in content.indices {
            let character = content[index]
            if character == "'", !isInDoubleQuote {
                isInSingleQuote.toggle()
            } else if character == "\"", !isInSingleQuote {
                isInDoubleQuote.toggle()
            } else if character == ":", !isInSingleQuote, !isInDoubleQuote {
                let next = content.index(after: index)
                guard next == content.endIndex || content[next].isWhitespace else {
                    continue
                }

                let key = String(content[..<index]).trimmingCharacters(in: .whitespaces)
                let value = next == content.endIndex ? "" : String(content[next...]).trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { return nil }
                return (unquote(key), value)
            }
        }

        return nil
    }

    private func parseScalar(_ rawValue: String) -> SimpleYAMLValue {
        let value = rawValue.trimmingCharacters(in: .whitespaces)
        if value.isEmpty || value == "~" || value.lowercased() == "null" {
            return .null
        }
        if value == "{}" {
            return .mapping([:])
        }
        if value == "[]" {
            return .sequence([])
        }
        return .scalar(unquote(value))
    }

    private func stripComment(from line: String) -> String {
        var isInSingleQuote = false
        var isInDoubleQuote = false
        var previous: Character?

        for index in line.indices {
            let character = line[index]
            if character == "'", !isInDoubleQuote {
                isInSingleQuote.toggle()
            } else if character == "\"", !isInSingleQuote {
                isInDoubleQuote.toggle()
            } else if character == "#", !isInSingleQuote, !isInDoubleQuote {
                if previous == nil || previous?.isWhitespace == true {
                    return String(line[..<index])
                }
            }
            previous = character
        }

        return line
    }

    private func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if value.first == "\"", value.last == "\"" {
            return String(value.dropFirst().dropLast())
        }
        if value.first == "'", value.last == "'" {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var copy = self
        while copy.last?.isWhitespace == true {
            copy.removeLast()
        }
        return copy
    }
}
