import Foundation

enum LogJSONLFormatter {
    nonisolated private static let maximumParsableLineBytes = 64 * 1024

    nonisolated static func formattedLines(from lines: [String]) -> [String] {
        lines.map(formatLine)
    }

    nonisolated static func formatLine(_ line: String) -> String {
        let candidate = jsonPayloadCandidate(in: line)
        guard let candidate,
              let formattedPayload = prettyPrintedJSON(candidate.payload) else {
            return line
        }

        guard !candidate.prefix.isEmpty else {
            return formattedPayload
        }

        var formattedLines = formattedPayload.components(separatedBy: .newlines)
        guard let firstLine = formattedLines.first else {
            return line
        }

        formattedLines[0] = candidate.prefix + firstLine
        return formattedLines.joined(separator: "\n")
    }

    nonisolated private static func jsonPayloadCandidate(in line: String) -> (prefix: String, payload: String)? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if startsLikeJSON(trimmedLine) {
            return ("", trimmedLine)
        }

        guard let separatorIndex = line.firstIndex(of: " ") else {
            return nil
        }

        let prefix = String(line[..<line.index(after: separatorIndex)])
        guard looksLikeKubernetesTimestampPrefix(prefix) else {
            return nil
        }

        let payload = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
        guard startsLikeJSON(payload) else {
            return nil
        }

        return (prefix, payload)
    }

    nonisolated private static func startsLikeJSON(_ text: String) -> Bool {
        text.first == "{" || text.first == "["
    }

    nonisolated private static func looksLikeKubernetesTimestampPrefix(_ prefix: String) -> Bool {
        guard prefix.count >= 21 else {
            return false
        }

        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 20
            && trimmed.dropFirst(4).first == "-"
            && trimmed.dropFirst(7).first == "-"
            && trimmed.contains("T")
    }

    nonisolated private static func prettyPrintedJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              data.count <= maximumParsableLineBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let prettyData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ) else {
            return nil
        }

        return String(data: prettyData, encoding: .utf8)
    }
}
