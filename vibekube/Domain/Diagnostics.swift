import CryptoKit
import Foundation

nonisolated enum DiagnosticsLevel: String, Codable, CaseIterable {
    case debug
    case info
    case warning
    case error
}

nonisolated struct DiagnosticsSettings: Equatable {
    var fileLoggingEnabled: Bool
    var includeClusterNames: Bool
    var retentionDays: Int
    var maxTotalMegabytes: Int

    static let `default` = DiagnosticsSettings(
        fileLoggingEnabled: false,
        includeClusterNames: false,
        retentionDays: 7,
        maxTotalMegabytes: 50
    )
}

nonisolated struct DiagnosticsEvent: Codable, Equatable, Identifiable {
    var id: UUID
    var timestamp: Date
    var level: DiagnosticsLevel
    var category: String
    var message: String
    var contextHash: String?
    var contextName: String?
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: DiagnosticsLevel,
        category: String,
        message: String,
        contextHash: String? = nil,
        contextName: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.contextHash = contextHash
        self.contextName = contextName
        self.metadata = metadata
    }
}

nonisolated enum DiagnosticsRedactor {
    static func hashIdentifier(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }

        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func sanitizedMetadata(_ metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [:]) { result, entry in
            result[entry.key] = sanitizedValue(entry.value, key: entry.key)
        }
    }

    static func sanitizedValue(_ value: String, key: String) -> String {
        if isSensitiveKey(key) || isSensitiveValue(value) {
            return "<redacted>"
        }
        return value
    }

    static func redactedText(_ text: String) -> String {
        guard !text.isEmpty else {
            return text
        }

        var redacted = text
        let rules: [(pattern: String, template: String, options: NSRegularExpression.Options)] = [
            (
                #"-----BEGIN [A-Z ]*(?:PRIVATE KEY|CERTIFICATE)-----.*?-----END [A-Z ]*(?:PRIVATE KEY|CERTIFICATE)-----"#,
                "<redacted>",
                [.caseInsensitive, .dotMatchesLineSeparators]
            ),
            (
                #"\b(Bearer)\s+[A-Za-z0-9._~+/=-]+"#,
                "$1 <redacted>",
                [.caseInsensitive]
            ),
            (
                #"\b(Authorization\s*[:=]\s*)(?!Bearer\s+)([^\s,;)}\]]+)"#,
                "$1<redacted>",
                [.caseInsensitive]
            ),
            (
                #"(["']?(?:token|id-token|access-token|refresh-token|password|passphrase|secret|client-key-data|client-certificate-data|clientKeyData|clientCertificateData|client-key|private-key)["']?\s*[:=]\s*["']?)([^"',;\s}\]]+)(["']?)"#,
                "$1<redacted>$3",
                [.caseInsensitive]
            ),
            (
                #"(--(?:token|password|secret|client-key|client-certificate)(?:=|\s+))([^\s]+)"#,
                "$1<redacted>",
                [.caseInsensitive]
            )
        ]

        for rule in rules {
            guard let expression = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
                continue
            }
            let range = NSRange(redacted.startIndex..<redacted.endIndex, in: redacted)
            redacted = expression.stringByReplacingMatches(
                in: redacted,
                options: [],
                range: range,
                withTemplate: rule.template
            )
        }

        return redacted
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let fragments = [
            "authorization",
            "bearer",
            "certificate",
            "client-key",
            "credential",
            "kubeconfig",
            "password",
            "private-key",
            "secret",
            "token"
        ]
        let normalizedKey = key.lowercased()
        return fragments.contains { normalizedKey.contains($0) }
    }

    private static func isSensitiveValue(_ value: String) -> Bool {
        let lowercasedValue = value.lowercased()
        return lowercasedValue.contains("bearer ") ||
            lowercasedValue.contains("begin private key") ||
            lowercasedValue.contains("begin rsa private key") ||
            lowercasedValue.contains("client-certificate-data") ||
            lowercasedValue.contains("client-key-data")
    }
}
