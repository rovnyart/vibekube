import Foundation

enum AIProviderShape: String, Codable, CaseIterable, Identifiable {
    case openAICompatible
    case anthropicCompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAICompatible:
            "OpenAI-compatible"
        case .anthropicCompatible:
            "Anthropic-compatible"
        }
    }
}

enum AIProviderPreset: String, Codable, CaseIterable, Identifiable {
    case openAI
    case anthropic
    case openRouter
    case zAI
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .anthropic:
            "Anthropic"
        case .openRouter:
            "OpenRouter"
        case .zAI:
            "Z.AI"
        case .custom:
            "Custom"
        }
    }

    var shape: AIProviderShape {
        switch self {
        case .openAI, .openRouter, .zAI, .custom:
            .openAICompatible
        case .anthropic:
            .anthropicCompatible
        }
    }

    var defaultBaseURLString: String {
        switch self {
        case .openAI:
            "https://api.openai.com/v1"
        case .anthropic:
            "https://api.anthropic.com"
        case .openRouter:
            "https://openrouter.ai/api/v1"
        case .zAI:
            "https://api.z.ai/api/paas/v4"
        case .custom:
            ""
        }
    }
}

struct AIProviderSettings: Codable, Equatable {
    var shape: AIProviderShape
    var preset: AIProviderPreset
    var baseURLString: String
    var selectedModelID: String?

    static let `default` = AIProviderSettings(
        shape: .openAICompatible,
        preset: .openAI,
        baseURLString: AIProviderPreset.openAI.defaultBaseURLString,
        selectedModelID: nil
    )

    var normalizedBaseURLString: String {
        baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasBaseURL: Bool {
        URL(string: normalizedBaseURLString)?.scheme?.hasPrefix("http") == true
    }

    var isComplete: Bool {
        hasBaseURL && selectedModelID?.isEmpty == false
    }
}

struct AISecretHeader: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var value: String

    init(id: UUID = UUID(), name: String, value: String) {
        self.id = id
        self.name = name
        self.value = value
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AIProviderSecrets: Codable, Equatable {
    var apiKey: String
    var headers: [AISecretHeader]

    static let empty = AIProviderSecrets(apiKey: "", headers: [])

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var usableHeaders: [AISecretHeader] {
        headers.filter { !$0.normalizedName.isEmpty && !$0.normalizedValue.isEmpty }
    }
}

struct AIModelInfo: Equatable, Identifiable {
    var id: String
    var displayName: String
    var owner: String?
    var contextLength: Int?

    var subtitle: String? {
        let parts = [
            owner,
            contextLength.map { "\($0.formatted()) ctx" }
        ].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

enum AIModelDiscoveryState: Equatable {
    case idle
    case loading
    case loaded([AIModelInfo])
    case failed(String)
}

enum AIAvailabilityState: Equatable {
    case unknown
    case checking
    case available(String)
    case unavailable(String)
}

struct AIChatRequest: Equatable {
    var systemPrompt: String
    var userPrompt: String
    var context: AIContextBundle?
}

struct AIChatResponse: Equatable {
    var text: String
    var modelID: String
}

struct AIChatStreamChunk: Equatable {
    var textDelta: String
    var modelID: String?
    var isFinished: Bool
}

struct AIContextBundle: Equatable {
    var title: String
    var identity: String
    var sections: [AIContextSection]

    var promptText: String {
        var lines = [
            "Context: \(title)",
            identity
        ]

        for section in sections {
            lines.append("")
            lines.append("## \(section.title)")
            lines.append(section.content)
        }

        return lines.joined(separator: "\n")
    }
}

struct AIContextSection: Equatable, Identifiable {
    var id: String
    var title: String
    var content: String

    init(id: String? = nil, title: String, content: String) {
        self.id = id ?? title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        self.title = title
        self.content = content
    }
}
