import Foundation

enum LogTextSanitizer {
    nonisolated static func stripANSISequences(from text: String) -> String {
        var sanitized = text
        for pattern in ansiPatterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression]
            )
        }
        return sanitized
    }

    private nonisolated static let ansiPatterns = [
        // Operating System Command sequences, often used for terminal titles.
        "\u{001B}\\][^\u{0007}\u{001B}]*(?:\u{0007}|\u{001B}\\\\)",
        // Control Sequence Introducer sequences, including color/style SGR codes.
        "\u{001B}\\[[0-?]*[ -/]*[@-~]",
        // Single-character ESC commands.
        "\u{001B}[@-Z\\\\-_]"
    ]
}
