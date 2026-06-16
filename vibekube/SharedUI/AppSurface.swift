import SwiftUI

private struct AppSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat
    var strokeColor: Color?

    func body(content: Content) -> some View {
        content
            .background(surfaceFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(strokeColor ?? defaultStroke)
            }
    }

    private var surfaceFill: Color {
        if colorScheme == .dark {
            return Color(nsColor: .controlBackgroundColor).opacity(0.70)
        }

        return Color(nsColor: .controlBackgroundColor).opacity(0.34)
    }

    private var defaultStroke: Color {
        Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.24 : 0.16)
    }
}

extension View {
    func appSurface(
        cornerRadius: CGFloat = 8,
        strokeColor: Color? = nil
    ) -> some View {
        modifier(AppSurfaceModifier(cornerRadius: cornerRadius, strokeColor: strokeColor))
    }
}
