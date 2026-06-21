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

    @Test func mutationRequestSendsPatchBodyDryRunAndDecodesResource() async throws {
        let client = try makeClient { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.path == "/apis/apps/v1/namespaces/vibekube-demo/deployments/echo-web")
            #expect(request.url?.query == "dryRun=All")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer demo-token")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/merge-patch+json")
            #expect(String(data: request.httpBody ?? Data(), encoding: .utf8) == #"{"spec":{"replicas":3}}"#)
            return .response(
                statusCode: 200,
                body: """
                {
                  "apiVersion": "apps/v1",
                  "kind": "Deployment",
                  "metadata": {
                    "name": "echo-web",
                    "namespace": "vibekube-demo"
                  }
                }
                """
            )
        }

        let result = try await client.mutate(
            KubernetesMutationRequest(
                verb: .patch,
                resource: deploymentResource(),
                namespace: "vibekube-demo",
                name: "echo-web",
                body: Data(#"{"spec":{"replicas":3}}"#.utf8),
                contentType: "application/merge-patch+json",
                dryRun: true
            )
        )

        #expect(result.statusCode == 200)
        #expect(result.resource?.summary.name == "echo-web")
        #expect(result.resource?.summary.kind == "Deployment")
        #expect(result.status == nil)
    }

    @Test func mutationRequestDecodesForbiddenStatus() async throws {
        let client = try makeClient { _ in
            .response(statusCode: 403, body: Self.statusBody(reason: "Forbidden", code: 403))
        }

        do {
            _ = try await client.mutate(deletePodRequest())
            Issue.record("Expected forbidden mutation status")
        } catch let error as KubernetesMutationError {
            #expect(error.httpStatusCode == 403)
            #expect(error.isForbidden)
            #expect(error.status?.reason == "Forbidden")
            #expect(error.status?.message == "mutation failed")
        }
    }

    @Test func mutationRequestDecodesNotFoundStatus() async throws {
        let client = try makeClient { _ in
            .response(statusCode: 404, body: Self.statusBody(reason: "NotFound", code: 404))
        }

        do {
            _ = try await client.mutate(deletePodRequest())
            Issue.record("Expected not-found mutation status")
        } catch let error as KubernetesMutationError {
            #expect(error.isNotFound)
            #expect(error.status?.reason == "NotFound")
        }
    }

    @Test func mutationRequestDecodesConflictStatusWithRetryHint() async throws {
        let client = try makeClient { _ in
            .response(
                statusCode: 409,
                body: Self.statusBody(reason: "Conflict", code: 409, retryAfterSeconds: 2)
            )
        }

        do {
            _ = try await client.mutate(deletePodRequest())
            Issue.record("Expected conflict mutation status")
        } catch let error as KubernetesMutationError {
            #expect(error.isConflict)
            #expect(error.retryAfterSeconds == 2)
        }
    }

    @Test func mutationRequestDecodesValidationCauses() async throws {
        let client = try makeClient { _ in
            .response(
                statusCode: 422,
                body: Self.statusBody(
                    reason: "Invalid",
                    code: 422,
                    causes: [
                        (field: "spec.replicas", message: "Invalid value: -1: must be greater than or equal to 0")
                    ]
                )
            )
        }

        do {
            _ = try await client.mutate(deletePodRequest())
            Issue.record("Expected validation mutation status")
        } catch let error as KubernetesMutationError {
            #expect(error.isValidationFailure)
            #expect(error.fieldCauses.first?.field == "spec.replicas")
            #expect(error.fieldCauses.first?.message?.contains("greater than or equal to 0") == true)
            #expect(error.localizedDescription.contains("spec.replicas"))
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

    private func deploymentResource() -> KubernetesDiscoveredResource {
        KubernetesDiscoveredResource(
            groupVersion: "apps/v1",
            resource: KubernetesAPIResource(
                name: "deployments",
                singularName: "",
                namespaced: true,
                kind: "Deployment",
                verbs: ["get", "list", "watch", "patch", "update"],
                shortNames: nil,
                categories: nil
            )
        )
    }

    private func podResource() -> KubernetesDiscoveredResource {
        KubernetesDiscoveredResource(
            groupVersion: "v1",
            resource: KubernetesAPIResource(
                name: "pods",
                singularName: "",
                namespaced: true,
                kind: "Pod",
                verbs: ["get", "list", "watch", "delete"],
                shortNames: nil,
                categories: nil
            )
        )
    }

    private func deletePodRequest() -> KubernetesMutationRequest {
        KubernetesMutationRequest(
            verb: .delete,
            resource: podResource(),
            namespace: "vibekube-demo",
            name: "echo-web-abc123"
        )
    }

    private nonisolated static func statusBody(
        reason: String,
        code: Int,
        retryAfterSeconds: Int? = nil,
        causes: [(field: String, message: String)] = []
    ) -> String {
        let retry = retryAfterSeconds.map { #","retryAfterSeconds":\#($0)"# } ?? ""
        let causeJSON = causes.map { cause in
            #"{"reason":"FieldValueInvalid","field":"\#(cause.field)","message":"\#(cause.message)"}"#
        }.joined(separator: ",")
        return """
        {
          "kind": "Status",
          "apiVersion": "v1",
          "status": "Failure",
          "message": "mutation failed",
          "reason": "\(reason)",
          "details": {
            "kind": "pods"\(retry),
            "causes": [\(causeJSON)]
          },
          "code": \(code)
        }
        """
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
