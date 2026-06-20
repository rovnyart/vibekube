import Foundation

enum ConnectionState: String, CaseIterable, Hashable {
    case disconnected
    case connecting
    case authenticating
    case connected
    case unauthorized
    case unavailable
    case certificateError
    case unsupportedAuth

    var title: String {
        switch self {
        case .disconnected:
            "Disconnected"
        case .connecting:
            "Connecting"
        case .authenticating:
            "Signing In"
        case .connected:
            "Connected"
        case .unauthorized:
            "Unauthorized"
        case .unavailable:
            "Unavailable"
        case .certificateError:
            "Certificate"
        case .unsupportedAuth:
            "Unsupported Auth"
        }
    }

    var systemImage: String {
        switch self {
        case .disconnected:
            "circle"
        case .connecting:
            "arrow.triangle.2.circlepath"
        case .authenticating:
            "person.crop.circle.badge.clock"
        case .connected:
            "checkmark.circle.fill"
        case .unauthorized:
            "lock.trianglebadge.exclamationmark"
        case .unavailable:
            "wifi.exclamationmark"
        case .certificateError:
            "checkmark.shield.trianglebadge.exclamationmark"
        case .unsupportedAuth:
            "person.badge.key"
        }
    }

    var canAttemptConnection: Bool {
        switch self {
        case .disconnected, .unavailable, .certificateError, .unauthorized:
            true
        case .connecting, .authenticating, .connected, .unsupportedAuth:
            false
        }
    }
}
