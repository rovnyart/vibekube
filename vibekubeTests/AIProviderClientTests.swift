import Foundation
import Testing
@testable import vibekube

@Suite(.serialized)
struct AIProviderClientTests {
    @Test func openAIModelDiscoveryUsesBearerAuthCustomHeadersAndBasePath() async throws {
        let client = makeClient { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/company/openai/v1/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-token")
            #expect(request.value(forHTTPHeaderField: "X-Team") == "platform")
            return .response(
                statusCode: 200,
                body: """
                {
                  "data": [
                    {
                      "id": "gpt-demo",
                      "owned_by": "openai",
                      "context_length": 128000
                    }
                  ]
                }
                """
            )
        }

        let models = try await client.listModels(
            settings: AIProviderSettings(
                shape: .openAICompatible,
                preset: .custom,
                baseURLString: "https://ai.example.com/company/openai/v1",
                selectedModelID: nil
            ),
            secrets: AIProviderSecrets(
                apiKey: "openai-token",
                headers: [AISecretHeader(name: "X-Team", value: "platform")]
            )
        )

        #expect(models == [
            AIModelInfo(id: "gpt-demo", displayName: "gpt-demo", owner: "openai", contextLength: 128_000)
        ])
    }

    @Test func anthropicModelDiscoveryUsesAPIKeyVersionHeaderAndSingleV1Path() async throws {
        let client = makeClient { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v1/models")
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "anthropic-token")
            #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            return .response(
                statusCode: 200,
                body: """
                {
                  "data": [
                    {
                      "id": "claude-demo",
                      "display_name": "Claude Demo",
                      "type": "model"
                    }
                  ]
                }
                """
            )
        }

        let models = try await client.listModels(
            settings: AIProviderSettings(
                shape: .anthropicCompatible,
                preset: .anthropic,
                baseURLString: "https://api.anthropic.com/v1",
                selectedModelID: nil
            ),
            secrets: AIProviderSecrets(apiKey: "anthropic-token", headers: [])
        )

        #expect(models == [
            AIModelInfo(id: "claude-demo", displayName: "Claude Demo", owner: "model", contextLength: nil)
        ])
    }

    @Test func openAIChatCompletionSendsSystemUserContextAndModel() async throws {
        let client = makeClient { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-token")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

            let body = try #require(JSONSerialization.jsonObject(with: Self.requestBodyData(from: request)) as? [String: Any])
            #expect(body["model"] as? String == "gpt-demo")
            #expect(body["temperature"] as? Double == 0.2)
            #expect(body["max_tokens"] as? Int == 1_200)

            let messages = try #require(body["messages"] as? [[String: String]])
            #expect(messages.count == 2)
            #expect(messages[0]["role"] == "system")
            #expect(messages[0]["content"] == "Stay careful.")
            #expect(messages[1]["role"] == "user")
            #expect(messages[1]["content"]?.contains("Use the following redacted Kubernetes context.") == true)
            #expect(messages[1]["content"]?.contains("Context: Deployment/echo-web") == true)
            #expect(messages[1]["content"]?.contains("User request:\nExplain") == true)

            return .response(
                statusCode: 200,
                body: """
                {
                  "model": "gpt-demo",
                  "choices": [
                    {
                      "message": {
                        "content": "It is healthy."
                      }
                    }
                  ]
                }
                """
            )
        }

        let response = try await client.complete(
            settings: AIProviderSettings(
                shape: .openAICompatible,
                preset: .openAI,
                baseURLString: "https://api.openai.com/v1",
                selectedModelID: "gpt-demo"
            ),
            secrets: AIProviderSecrets(apiKey: "openai-token", headers: []),
            request: AIChatRequest(
                systemPrompt: "Stay careful.",
                userPrompt: "Explain",
                context: AIContextBundle(
                    title: "Deployment/echo-web",
                    identity: "Resource: Deployment/echo-web",
                    sections: [AIContextSection(title: "Status", content: "Available")]
                )
            )
        )

        #expect(response == AIChatResponse(text: "It is healthy.", modelID: "gpt-demo"))
    }

    @MainActor
    @Test func appModelRequiresURLSecretAndModelAndPreservesAnthropicCustomShape() {
        var preferences = InMemoryUserPreferences()
        preferences.aiProviderSettings = AIProviderSettings(
            shape: .anthropicCompatible,
            preset: .anthropic,
            baseURLString: "https://api.anthropic.com",
            selectedModelID: nil
        )
        let model = AppModel(clusters: ClusterSummary.preview, userPreferences: preferences)

        #expect(!model.aiIsConfigured)

        model.saveAIProviderSecrets(apiKey: "test-key", headers: [])
        #expect(!model.aiIsConfigured)

        model.setAISelectedModelID("claude-demo")
        #expect(model.aiIsConfigured)

        model.setAIProviderPreset(.custom)
        #expect(model.aiProviderSettings.shape == .anthropicCompatible)
        #expect(model.aiProviderSettings.preset == .custom)
        #expect(!model.aiIsConfigured)
    }

    private func makeClient(
        handler: @escaping @Sendable (URLRequest) async throws -> AIProviderMockURLProtocol.MockResponse
    ) -> AIProviderClient {
        AIProviderMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIProviderMockURLProtocol.self]
        return AIProviderClient(urlSession: URLSession(configuration: configuration))
    }

    private nonisolated static func requestBodyData(from request: URLRequest) -> Data {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            body.append(buffer, count: count)
        }
        return body
    }
}

private final class AIProviderMockURLProtocol: URLProtocol {
    enum MockResponse {
        case response(statusCode: Int, body: String)
        case failure(Error)
    }

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) async throws -> MockResponse)?

    private var loadingTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: AIProviderClientError.invalidResponse)
            return
        }

        loadingTask = Task {
            do {
                switch try await handler(request) {
                case .response(let statusCode, let body):
                    let response = HTTPURLResponse(
                        url: request.url ?? URL(string: "https://ai.example.com")!,
                        statusCode: statusCode,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: Data(body.utf8))
                    client?.urlProtocolDidFinishLoading(self)
                case .failure(let error):
                    client?.urlProtocol(self, didFailWithError: error)
                }
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
    }
}
