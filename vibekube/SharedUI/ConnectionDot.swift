import SwiftUI

struct ConnectionDot: View {
    let state: ConnectionState

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 8, height: 8)
            .accessibilityLabel(state.title)
    }

    private var tint: Color {
        switch state {
        case .connected:
            .green
        case .connecting:
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
