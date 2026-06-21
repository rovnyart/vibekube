import Foundation

protocol AIProviderServicing {
    func listModels(settings: AIProviderSettings, secrets: AIProviderSecrets) async throws -> [AIModelInfo]
    func testConnection(settings: AIProviderSettings, secrets: AIProviderSecrets) async throws -> String
    func complete(settings: AIProviderSettings, secrets: AIProviderSecrets, request: AIChatRequest) async throws -> AIChatResponse
    func streamComplete(
        settings: AIProviderSettings,
        secrets: AIProviderSecrets,
        request: AIChatRequest
    ) -> AsyncThrowingStream<AIChatStreamChunk, Error>
}

enum AIProviderClientError: LocalizedError {
    case missingBaseURL
    case missingAPIKey
    case missingModel
    case invalidResponse
    case httpStatus(Int, String)
    case noModels
    case noText

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            "AI base URL is missing or invalid."
        case .missingAPIKey:
            "AI API key is missing."
        case .missingModel:
            "Select an AI model first."
        case .invalidResponse:
            "The AI provider returned an unexpected response."
        case .httpStatus(let status, let message):
            "AI provider returned HTTP \(status): \(message)"
        case .noModels:
            "The provider did not return any models."
        case .noText:
            "The AI provider response did not contain text."
        }
    }
}

struct AIProviderClient: AIProviderServicing {
    var urlSession: URLSession = .shared

    func listModels(settings: AIProviderSettings, secrets: AIProviderSecrets) async throws -> [AIModelInfo] {
        switch settings.shape {
        case .openAICompatible:
            return try await listOpenAIModels(settings: settings, secrets: secrets)
        case .anthropicCompatible:
            return try await listAnthropicModels(settings: settings, secrets: secrets)
        }
    }

    func testConnection(settings: AIProviderSettings, secrets: AIProviderSecrets) async throws -> String {
        let models = try await listModels(settings: settings, secrets: secrets)
        guard !models.isEmpty else {
            throw AIProviderClientError.noModels
        }

        if let selectedModelID = settings.selectedModelID,
           models.contains(where: { $0.id == selectedModelID }) {
            return "Ready with \(selectedModelID)."
        }

        return "Connected. \(models.count.formatted()) models available."
    }

    func complete(
        settings: AIProviderSettings,
        secrets: AIProviderSecrets,
        request: AIChatRequest
    ) async throws -> AIChatResponse {
        switch settings.shape {
        case .openAICompatible:
            return try await completeOpenAI(settings: settings, secrets: secrets, request: request)
        case .anthropicCompatible:
            return try await completeAnthropic(settings: settings, secrets: secrets, request: request)
        }
    }

    func streamComplete(
        settings: AIProviderSettings,
        secrets: AIProviderSecrets,
        request chatRequest: AIChatRequest
    ) -> AsyncThrowingStream<AIChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch settings.shape {
                    case .openAICompatible:
                        try await streamOpenAI(settings: settings, secrets: secrets, request: chatRequest, continuation: continuation)
                    case .anthropicCompatible:
                        try await streamAnthropic(settings: settings, secrets: secrets, request: chatRequest, continuation: continuation)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func listOpenAIModels(
        settings: AIProviderSettings,
        secrets: AIProviderSecrets
    ) async throws -> [AIModelInfo] {
        var request = try URLRequest(url: endpoint("/models", settings: settings))
        request.httpMethod = "GET"
        try applyOpenAIHeaders(to: &request, secrets: secrets)

        let data = try await validatedData(for: request)
        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return response.data
            .map { model in
                AIModelInfo(
                    id: model.id,
                    displayName: model.name ?? model.id,
                    owner: model.ownedBy,
                    contextLength: model.contextLength
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func listAnthropicModels(
        settings: AIProviderSettings,
        secrets: AIProviderSecrets
    ) async throws -> [AIModelInfo] {
        var request = try URLRequest(url: endpoint("/v1/models", settings: settings, stripVersionPath: true))
        request.httpMethod = "GET"
        try applyAnthropicHeaders(to: &request, secrets: secrets)

        let data = try await validatedData(for: request)
        let response = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
        return response.data
            .map { model in
                AIModelInfo(
                    id: model.id,
                    displayName: model.displayName ?? model.id,
                    owner: model.type,
                    contextLength: nil
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func completeOpenAI(
        settings: AIProviderSettings,
        secrets: AIProviderSecrets,
        request chatRequest: AIChatRequest
    ) async throws -> AIChatResponse {
        guard let modelID = settings.selectedModelID, !modelID.isEmpty else {
            throw AIProviderClientError.missingModel
        }

        let messages = [
            OpenAIChatMessage(role: "system", content: chatRequest.systemPrompt),
            OpenAIChatMessage(role: "user", content: userPrompt(chatRequest))
        ]
        let payload = OpenAIChatRequest(
            model: modelID,
            messages: messages,
            maxCompletionTokens: 1_200
        )

        var request = try URLRequest(url: endpoint("/chat/completions", settings: settings))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try applyOpenAIHeaders(to: &request, secrets: secrets)

        let data = try await validatedData(for: request)
        let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let text = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw AIProviderClientError.noText
        }
        return AIChatResponse(text: text, modelID: response.model ?? modelID)
    }

    private func streamOpenAI(
        settings: AIProviderSettings,
        secrets: AIProviderSecrets,
        request chatRequest: AIChatRequest,
        continuation: AsyncThrowingStream<AIChatStreamChunk, Error>.Continuation
    ) async throws {
        guard let modelID = settings.selectedModelID, !modelID.isEmpty else {
            throw AIProviderClientError.missingModel
        }

        let messages = [
            OpenAIChatMessage(role: "system", content: chatRequest.systemPrompt),
            OpenAIChatMessage(role: "user", content: userPrompt(chatRequest))
        ]
        let payload = OpenAIChatRequest(
            model: modelID,
            messages: messages,
            maxCompletionTokens: 1_200,
            stream: true
        )

        var request = try URLRequest(url: endpoint("/chat/completions", settings: settings))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        try applyOpenAIHeaders(to: &request, secrets: secrets)

        let (bytes, response) = try await urlSession.bytes(for: request)
        try validateStreamResponse(response, bytes: bytes)

        var emittedText = false
        try await streamServerSentEvents(from: bytes) { event in
            for data in event.data {
                if data == "[DONE]" {
                    continuation.yield(AIChatStreamChunk(textDelta: "", modelID: modelID, isFinished: true))
                    continuation.finish()
                    return
                }

                guard let eventData = data.data(using: .utf8) else {
                    continue
                }
                let chunk = try JSONDecoder().decode(OpenAIChatStreamResponse.self, from: eventData)
                for choice in chunk.choices {
                    if let content = choice.delta.content, !content.isEmpty {
                        emittedText = true
                        continuation.yield(
                            AIChatStreamChunk(
                                textDelta: content,
                                modelID: chunk.model ?? modelID,
                                isFinished: false
                            )
                        )
                    }
                }
            }
        }

        guard emittedText else {
            throw AIProviderClientError.noText
        }
        continuation.yield(AIChatStreamChunk(textDelta: "", modelID: modelID, isFinished: true))
        continuation.finish()
    }

    private func completeAnthropic(
        settings: AIProviderSettings,
        secrets: AIProviderSecrets,
        request chatRequest: AIChatRequest
    ) async throws -> AIChatResponse {
        guard let modelID = settings.selectedModelID, !modelID.isEmpty else {
            throw AIProviderClientError.missingModel
        }

        let payload = AnthropicMessageRequest(
            model: modelID,
            maxTokens: 1_200,
            system: chatRequest.systemPrompt,
            messages: [
                AnthropicMessage(role: "user", content: userPrompt(chatRequest))
            ]
        )

        var request = try URLRequest(url: endpoint("/v1/messages", settings: settings, stripVersionPath: true))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try applyAnthropicHeaders(to: &request, secrets: secrets)

        let data = try await validatedData(for: request)
        let response = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
        let text = response.content
            .compactMap { item in item.type == "text" ? item.text : nil }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AIProviderClientError.noText
        }
        return AIChatResponse(text: text, modelID: response.model ?? modelID)
    }

    private func streamAnthropic(
        settings: AIProviderSettings,
        secrets: AIProviderSecrets,
        request chatRequest: AIChatRequest,
        continuation: AsyncThrowingStream<AIChatStreamChunk, Error>.Continuation
    ) async throws {
        guard let modelID = settings.selectedModelID, !modelID.isEmpty else {
            throw AIProviderClientError.missingModel
        }

        let payload = AnthropicMessageRequest(
            model: modelID,
            maxTokens: 1_200,
            system: chatRequest.systemPrompt,
            messages: [
                AnthropicMessage(role: "user", content: userPrompt(chatRequest))
            ],
            stream: true
        )

        var request = try URLRequest(url: endpoint("/v1/messages", settings: settings, stripVersionPath: true))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        try applyAnthropicHeaders(to: &request, secrets: secrets)

        let (bytes, response) = try await urlSession.bytes(for: request)
        try validateStreamResponse(response, bytes: bytes)

        var emittedText = false
        try await streamServerSentEvents(from: bytes) { event in
            for data in event.data {
                guard let eventData = data.data(using: .utf8) else {
                    continue
                }
                let chunk = try JSONDecoder().decode(AnthropicStreamEvent.self, from: eventData)
                if chunk.type == "message_stop" {
                    continuation.yield(AIChatStreamChunk(textDelta: "", modelID: chunk.message?.model ?? modelID, isFinished: true))
                    continuation.finish()
                    return
                }
                if let text = chunk.delta?.text, !text.isEmpty {
                    emittedText = true
                    continuation.yield(
                        AIChatStreamChunk(
                            textDelta: text,
                            modelID: chunk.message?.model ?? modelID,
                            isFinished: false
                        )
                    )
                }
            }
        }

        guard emittedText else {
            throw AIProviderClientError.noText
        }
        continuation.yield(AIChatStreamChunk(textDelta: "", modelID: modelID, isFinished: true))
        continuation.finish()
    }

    private func userPrompt(_ request: AIChatRequest) -> String {
        guard let context = request.context else {
            return request.userPrompt
        }

        return [
            "Use the following redacted Kubernetes context. Name the context you used in your answer.",
            context.promptText,
            "",
            "User request:",
            request.userPrompt
        ].joined(separator: "\n")
    }

    private func endpoint(
        _ path: String,
        settings: AIProviderSettings,
        stripVersionPath: Bool = false
    ) throws -> URL {
        guard var components = URLComponents(string: settings.normalizedBaseURLString),
              components.scheme?.hasPrefix("http") == true else {
            throw AIProviderClientError.missingBaseURL
        }

        var basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if stripVersionPath, basePath == "v1" {
            basePath = ""
        }

        let targetPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, targetPath].filter { !$0.isEmpty }.joined(separator: "/"))

        guard let url = components.url else {
            throw AIProviderClientError.missingBaseURL
        }
        return url
    }

    private func applyOpenAIHeaders(to request: inout URLRequest, secrets: AIProviderSecrets) throws {
        let apiKey = secrets.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw AIProviderClientError.missingAPIKey
        }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        applyCustomHeaders(to: &request, secrets: secrets)
    }

    private func applyAnthropicHeaders(to request: inout URLRequest, secrets: AIProviderSecrets) throws {
        let apiKey = secrets.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw AIProviderClientError.missingAPIKey
        }
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        applyCustomHeaders(to: &request, secrets: secrets)
    }

    private func applyCustomHeaders(to request: inout URLRequest, secrets: AIProviderSecrets) {
        for header in secrets.usableHeaders {
            request.setValue(header.normalizedValue, forHTTPHeaderField: header.normalizedName)
        }
    }

    private func validatedData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data.prefix(1_000), encoding: .utf8) ?? "No response body"
            throw AIProviderClientError.httpStatus(httpResponse.statusCode, message)
        }

        return data
    }

    private func validateStreamResponse(
        _ response: URLResponse,
        bytes: URLSession.AsyncBytes
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIProviderClientError.httpStatus(httpResponse.statusCode, "Streaming request failed.")
        }
    }

    private func streamServerSentEvents(
        from bytes: URLSession.AsyncBytes,
        handle: (ServerSentEvent) throws -> Void
    ) async throws {
        var currentEvent = ServerSentEvent()
        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .newlines)
            if line.isEmpty {
                if !currentEvent.data.isEmpty || currentEvent.event != nil {
                    try handle(currentEvent)
                    currentEvent = ServerSentEvent()
                }
                continue
            }

            if line.hasPrefix("event:") {
                currentEvent.event = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                currentEvent.data.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
            }
        }

        if !currentEvent.data.isEmpty || currentEvent.event != nil {
            try handle(currentEvent)
        }
    }
}

private struct ServerSentEvent {
    var event: String?
    var data: [String] = []
}

private struct OpenAIModelsResponse: Decodable {
    var data: [OpenAIModel]
}

private struct OpenAIModel: Decodable {
    var id: String
    var name: String?
    var ownedBy: String?
    var contextLength: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownedBy = "owned_by"
        case contextLength = "context_length"
    }
}

private struct AnthropicModelsResponse: Decodable {
    var data: [AnthropicModel]
}

private struct AnthropicModel: Decodable {
    var id: String
    var displayName: String?
    var type: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case type
    }
}

private struct OpenAIChatRequest: Encodable {
    var model: String
    var messages: [OpenAIChatMessage]
    var maxCompletionTokens: Int
    var stream: Bool?

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxCompletionTokens = "max_completion_tokens"
        case stream
    }
}

private struct OpenAIChatMessage: Encodable {
    var role: String
    var content: String
}

private struct OpenAIChatResponse: Decodable {
    var model: String?
    var choices: [OpenAIChatChoice]
}

private struct OpenAIChatChoice: Decodable {
    var message: OpenAIChatResponseMessage
}

private struct OpenAIChatResponseMessage: Decodable {
    var content: String
}

private struct OpenAIChatStreamResponse: Decodable {
    var model: String?
    var choices: [OpenAIChatStreamChoice]
}

private struct OpenAIChatStreamChoice: Decodable {
    var delta: OpenAIChatStreamDelta
}

private struct OpenAIChatStreamDelta: Decodable {
    var content: String?
}

private struct AnthropicMessageRequest: Encodable {
    var model: String
    var maxTokens: Int
    var system: String
    var messages: [AnthropicMessage]
    var stream: Bool?

    private enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case stream
    }
}

private struct AnthropicMessage: Encodable {
    var role: String
    var content: String
}

private struct AnthropicMessageResponse: Decodable {
    var model: String?
    var content: [AnthropicContent]
}

private struct AnthropicContent: Decodable {
    var type: String
    var text: String?
}

private struct AnthropicStreamEvent: Decodable {
    var type: String
    var delta: AnthropicStreamDelta?
    var message: AnthropicStreamMessage?
}

private struct AnthropicStreamDelta: Decodable {
    var text: String?
}

private struct AnthropicStreamMessage: Decodable {
    var model: String?
}
