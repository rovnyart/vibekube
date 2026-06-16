import Foundation

final class DefaultKubernetesAPIClient: KubernetesAPIClient {
    private let configuration: KubernetesClientConfiguration
    private let delegate: KubernetesURLSessionDelegate
    private let session: URLSession

    init(configuration: KubernetesClientConfiguration) throws {
        guard !configuration.credential.requiresExecResolution else {
            throw KubernetesClientError.unsupportedAuthentication("Exec credentials must be resolved before creating a Kubernetes API client.")
        }

        self.configuration = configuration

        self.delegate = try KubernetesURLSessionDelegate(configuration: configuration)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 15
        sessionConfiguration.timeoutIntervalForResource = 30

        self.session = URLSession(
            configuration: sessionConfiguration,
            delegate: self.delegate,
            delegateQueue: nil
        )
    }

    func version() async throws -> KubernetesVersion {
        try await get(path: "/version")
    }

    func apiVersions() async throws -> KubernetesAPIVersions {
        try await get(path: "/api")
    }

    func apiGroups() async throws -> KubernetesAPIGroupList {
        try await get(path: "/apis")
    }

    func resources(groupVersion: String) async throws -> KubernetesAPIResourceList {
        if groupVersion.contains("/") {
            try await get(path: "/apis/\(groupVersion)")
        } else {
            try await get(path: "/api/\(groupVersion)")
        }
    }

    func namespaces() async throws -> KubernetesNamespaceList {
        try await get(path: "/api/v1/namespaces")
    }

    func resourceList(
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        try await get(path: resource.listPath(namespace: namespace))
    }

    func resourceWatch(
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        resourceVersion: String?
    ) -> AsyncThrowingStream<KubernetesWatchEvent<KubernetesUnstructuredResource>, Error> {
        let queryItems = Self.watchQueryItems(resourceVersion: resourceVersion)
        let textStream = streamText(
            path: resource.listPath(namespace: namespace),
            queryItems: queryItems
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let decoder = JSONDecoder()
                    for try await line in textStream {
                        try Task.checkCancellation()
                        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            continue
                        }

                        let event = try decoder.decode(
                            KubernetesWatchEvent<KubernetesUnstructuredResource>.self,
                            from: Data(line.utf8)
                        )
                        continuation.yield(event)
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func resourceDetail(
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesResourceDetail {
        try await get(path: resource.itemPath(namespace: namespace, name: name))
    }

    func resourceEvents(
        eventsResource: KubernetesDiscoveredResource,
        namespace: String?,
        involvedKind: String,
        involvedName: String,
        involvedUID: String?
    ) async throws -> KubernetesResourceEventList {
        try await get(
            path: eventsResource.listPath(namespace: namespace),
            queryItems: [
                URLQueryItem(
                    name: "fieldSelector",
                    value: Self.eventFieldSelector(
                        eventsResource: eventsResource,
                        namespace: namespace,
                        involvedKind: involvedKind,
                        involvedName: involvedName,
                        involvedUID: involvedUID
                    )
                )
            ]
        )
    }

    func nodeMetrics() async throws -> KubernetesNodeMetricsList {
        try await get(path: "/apis/metrics.k8s.io/v1beta1/nodes")
    }

    func podMetrics(namespace: String?) async throws -> KubernetesPodMetricsList {
        if let namespace, !namespace.isEmpty {
            return try await get(path: "/apis/metrics.k8s.io/v1beta1/namespaces/\(namespace.kubernetesPathSegment)/pods")
        }

        return try await get(path: "/apis/metrics.k8s.io/v1beta1/pods")
    }

    func podLogs(
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) async throws -> String {
        try await getText(
            path: Self.podLogPath(namespace: namespace, podName: podName),
            queryItems: options.queryItems
        )
    }

    func podLogStream(
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) -> AsyncThrowingStream<String, Error> {
        streamText(
            path: Self.podLogPath(namespace: namespace, podName: podName),
            queryItems: options.queryItems,
            timeoutInterval: 3_600
        )
    }

    private func streamText(
        path: String,
        queryItems: [URLQueryItem],
        timeoutInterval: TimeInterval = 3_600
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            var request = Self.textRequest(
                configuration: configuration,
                path: path,
                queryItems: queryItems
            )
            request.timeoutInterval = timeoutInterval
            applyAuthentication(to: &request)

            let task = session.dataTask(with: request)
            delegate.registerStream(
                task: task,
                continuation: continuation,
                errorMapper: Self.error(from:statusCode:)
            )
            task.resume()

            continuation.onTermination = { _ in
                task.cancel()
                self.delegate.unregisterStream(task: task)
            }
        }
    }

    private func get<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        var components = URLComponents(url: configuration.url(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        var request = URLRequest(url: components?.url ?? configuration.url(path: path))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuthentication(to: &request)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw KubernetesClientError.badResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw Self.error(from: data, statusCode: httpResponse.statusCode)
            }

            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw KubernetesClientError.decoding(error.localizedDescription)
            }
        } catch let error as KubernetesClientError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw mappedTransportError(error)
        }
    }

    private func getText(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> String {
        var request = Self.textRequest(configuration: configuration, path: path, queryItems: queryItems)
        applyAuthentication(to: &request)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw KubernetesClientError.badResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw Self.error(from: data, statusCode: httpResponse.statusCode)
            }

            return String(decoding: data, as: UTF8.self)
        } catch let error as KubernetesClientError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw mappedTransportError(error)
        }
    }

    private func mappedTransportError(_ error: Error) -> KubernetesClientError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled,
           !Task.isCancelled,
           let trustMessage = delegate.consumeServerTrustErrorMessage() {
            return .certificateError(trustMessage)
        }

        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorSecureConnectionFailed {
            return .certificateError(Self.transportDiagnosticMessage(from: nsError))
        }

        return .unavailable(error.localizedDescription)
    }

    private static func transportDiagnosticMessage(from error: NSError) -> String {
        var details = [
            error.localizedDescription,
            "NSURLError \(error.code)"
        ]

        var underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        var seenUnderlying = Set<String>()
        while let current = underlying {
            let key = "\(current.domain)|\(current.code)"
            guard seenUnderlying.insert(key).inserted else {
                break
            }
            details.append("\(current.domain) \(current.code): \(current.localizedDescription)")
            underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        return details.joined(separator: " · ")
    }

    private static func textRequest(
        configuration: KubernetesClientConfiguration,
        path: String,
        queryItems: [URLQueryItem]
    ) -> URLRequest {
        var components = URLComponents(url: configuration.url(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        var request = URLRequest(url: components?.url ?? configuration.url(path: path))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func podLogPath(namespace: String, podName: String) -> String {
        "/api/v1/namespaces/\(namespace.kubernetesPathSegment)/pods/\(podName.kubernetesPathSegment)/log"
    }

    private static func watchQueryItems(resourceVersion: String?) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "watch", value: "true"),
            URLQueryItem(name: "allowWatchBookmarks", value: "true"),
            URLQueryItem(name: "timeoutSeconds", value: "300")
        ]

        if let resourceVersion, !resourceVersion.isEmpty {
            items.append(URLQueryItem(name: "resourceVersion", value: resourceVersion))
        }

        return items
    }

    private func applyAuthentication(to request: inout URLRequest) {
        if case .bearerToken(let token) = configuration.credential {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private static func error(from data: Data, statusCode: Int) -> KubernetesClientError {
        let status = try? JSONDecoder().decode(KubernetesStatus.self, from: data)
        let message = status?.message

        switch statusCode {
        case 401, 403:
            return .unauthorized(message ?? "The cluster rejected the credentials.")
        default:
            return .statusCode(statusCode, message)
        }
    }

    private static func eventFieldSelector(
        eventsResource: KubernetesDiscoveredResource,
        namespace: String?,
        involvedKind: String,
        involvedName: String,
        involvedUID: String?
    ) -> String {
        let prefix = eventsResource.group == "events.k8s.io" ? "regarding" : "involvedObject"

        if let involvedUID, !involvedUID.isEmpty {
            return "\(prefix).uid=\(involvedUID)"
        }

        var selectors = [
            "\(prefix).kind=\(involvedKind)",
            "\(prefix).name=\(involvedName)"
        ]
        if let namespace, !namespace.isEmpty {
            selectors.append("\(prefix).namespace=\(namespace)")
        }
        return selectors.joined(separator: ",")
    }
}
