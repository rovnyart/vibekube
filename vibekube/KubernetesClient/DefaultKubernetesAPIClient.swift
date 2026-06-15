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
        var request = URLRequest(url: configuration.url(path: "/version"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if case .bearerToken(let token) = configuration.credential {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw KubernetesClientError.badResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw Self.error(from: data, statusCode: httpResponse.statusCode)
            }

            do {
                return try JSONDecoder().decode(KubernetesVersion.self, from: data)
            } catch {
                throw KubernetesClientError.decoding(error.localizedDescription)
            }
        } catch let error as KubernetesClientError {
            throw error
        } catch {
            throw KubernetesClientError.unavailable(error.localizedDescription)
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
}
