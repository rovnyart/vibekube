import Foundation
import Testing
@testable import vibekube

@MainActor
@Suite(.serialized)
struct KubernetesAPIClientTests {

    @Test func versionRequestDecodesSuccessfulResponseAndSendsBearerToken() async throws {
        let client = try makeClient { request in
            #expect(request.url?.path == "/version")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer demo-token")
            return .response(
                statusCode: 200,
                body: """
                {
                  "major": "1",
                  "minor": "30",
                  "gitVersion": "v1.30.0"
                }
                """
            )
        }

        let version = try await client.version()

        #expect(version.gitVersion == "v1.30.0")
    }

    @Test func versionRequestMapsAuthFailureStatus() async throws {
        let client = try makeClient { _ in
            .response(
                statusCode: 401,
                body: """
                {
                  "kind": "Status",
                  "apiVersion": "v1",
                  "status": "Failure",
                  "message": "token expired",
                  "reason": "Unauthorized",
                  "code": 401
                }
                """
            )
        }

        do {
            _ = try await client.version()
            Issue.record("Expected unauthorized error")
        } catch let error as KubernetesClientError {
            #expect(error == .unauthorized("token expired"))
            #expect(error.connectionState == .unauthorized)
        }
    }

    @Test func versionRequestMapsTimeoutAsUnavailable() async throws {
        let client = try makeClient { _ in
            .failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
        }

        do {
            _ = try await client.version()
            Issue.record("Expected unavailable error")
        } catch let error as KubernetesClientError {
            guard case .unavailable = error else {
                Issue.record("Expected unavailable error, got \(error)")
                return
            }
            #expect(error.connectionState == .unavailable)
        }
    }

    @Test func versionRequestPropagatesCancellation() async throws {
        let client = try makeClient { _ in
            .hanging
        }

        let task = Task {
            try await client.version()
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
        }
    }

    @Test func versionRequestMapsMalformedJSONAsDecodingError() async throws {
        let client = try makeClient { _ in
            .response(statusCode: 200, body: "{")
        }

        do {
            _ = try await client.version()
            Issue.record("Expected decoding error")
        } catch let error as KubernetesClientError {
            guard case .decoding(let message) = error else {
                Issue.record("Expected decoding error, got \(error)")
                return
            }
            #expect(!message.isEmpty)
        }
    }

    private func makeClient(
        handler: @escaping @Sendable (URLRequest) async throws -> MockURLProtocol.MockResponse
    ) throws -> DefaultKubernetesAPIClient {
        MockURLProtocol.handler = handler
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]
        return try DefaultKubernetesAPIClient(
            configuration: try clientConfiguration(),
            sessionConfiguration: sessionConfiguration
        )
    }

    private func clientConfiguration() throws -> KubernetesClientConfiguration {
        let kubeconfig = try KubeconfigParser(
            source: KubeconfigSource(url: URL(fileURLWithPath: "/tmp/kube/config.yaml"))
        ).parse(
            """
            clusters:
            - name: demo
              cluster:
                server: https://demo.example.com
            contexts:
            - name: demo
              context:
                cluster: demo
                user: demo-user
            users:
            - name: demo-user
              user:
                token: demo-token
            """
        )
        return try KubernetesClientConfiguration(contextName: "demo", kubeconfig: kubeconfig)
    }
}

private final class MockURLProtocol: URLProtocol {
    enum MockResponse {
        case response(statusCode: Int, body: String)
        case failure(Error)
        case hanging
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
            client?.urlProtocol(self, didFailWithError: KubernetesClientError.badResponse)
            return
        }

        loadingTask = Task {
            do {
                switch try await handler(request) {
                case .response(let statusCode, let body):
                    let response = HTTPURLResponse(
                        url: request.url ?? URL(string: "https://demo.example.com")!,
                        statusCode: statusCode,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: Data(body.utf8))
                    client?.urlProtocolDidFinishLoading(self)
                case .failure(let error):
                    client?.urlProtocol(self, didFailWithError: error)
                case .hanging:
                    try await Task.sleep(nanoseconds: 5_000_000_000)
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
