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
            "Invalid kubeconfig: \(Self.redacted(message))"
        case .unsupportedAuthentication(let message):
            "Unsupported authentication: \(Self.redacted(message))"
        case .execCredential(let message):
            Self.redacted(message)
        case .unauthorized(let message):
            message.isEmpty ? "The cluster rejected the credentials." : Self.redacted(message)
        case .unavailable(let message):
            Self.redacted(message)
        case .certificateError(let message):
            "TLS certificate error: \(Self.redacted(message))"
        case .badResponse:
            "The Kubernetes API returned an unreadable response."
        case .statusCode(let code, let message):
            if let message, !message.isEmpty {
                "Kubernetes API returned HTTP \(code): \(Self.redacted(message))"
            } else {
                "Kubernetes API returned HTTP \(code)."
            }
        case .decoding(let message):
            "Could not decode Kubernetes API response: \(Self.redacted(message))"
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

    private static func redacted(_ message: String) -> String {
        DiagnosticsRedactor.redactedText(message)
    }
}
