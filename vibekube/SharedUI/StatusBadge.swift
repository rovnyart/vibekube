import SwiftUI

struct StatusBadge: View {
    let state: ConnectionState

    var body: some View {
        Label(state.title, systemImage: state.systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityIdentifier("connection.status")
    }

    private var tint: Color {
        switch state {
        case .connected:
            .green
        case .connecting, .authenticating:
            .blue
        case .unauthorized, .certificateError, .unsupportedAuth:
            .orange
        case .unavailable:
            .red
        case .disconnected:
            .secondary
        }
    }
}
