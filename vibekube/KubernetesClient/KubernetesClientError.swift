import Foundation

enum KubernetesClientError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case unsupportedAuthentication(String)
    case execCredential(String)
    case unauthorized(String)
    case unavailable(String)
    case certificateError(String)
    case badResponse
    case statusCode(Int, String?)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            "Invalid kubeconfig: \(message)"
        case .unsupportedAuthentication(let message):
            "Unsupported authentication: \(message)"
        case .execCredential(let message):
            message
        case .unauthorized(let message):
            message.isEmpty ? "The cluster rejected the credentials." : message
        case .unavailable(let message):
            message
        case .certificateError(let message):
            "TLS certificate error: \(message)"
        case .badResponse:
            "The Kubernetes API returned an unreadable response."
        case .statusCode(let code, let message):
            if let message, !message.isEmpty {
                "Kubernetes API returned HTTP \(code): \(message)"
            } else {
                "Kubernetes API returned HTTP \(code)."
            }
        case .decoding(let message):
            "Could not decode Kubernetes API response: \(message)"
        }
    }

    var connectionState: ConnectionState {
        switch self {
        case .unsupportedAuthentication:
            .unsupportedAuth
        case .execCredential, .unauthorized:
            .unauthorized
        case .certificateError:
            .certificateError
        case .invalidConfiguration, .unavailable, .badResponse, .statusCode, .decoding:
            .unavailable
        }
    }
}
