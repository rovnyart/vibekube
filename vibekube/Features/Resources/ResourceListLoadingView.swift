import SwiftUI

struct ResourceListLoadingView: View {
    let title: String
    let progress: ResourceListLoadingProgress
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 5) {
                Text(title)
                    .font(.headline)

                Text(progressText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button(role: .cancel, action: cancel) {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var progressText: String {
        guard progress.pageCount > 0 else {
            return "Waiting for first response"
        }

        var parts = [
            "\(progress.itemCount) items",
            "\(progress.pageCount) \(progress.pageCount == 1 ? "page" : "pages")"
        ]

        if let remainingItemCount = progress.remainingItemCount {
            parts.append("\(remainingItemCount) remaining")
        }

        return parts.joined(separator: " · ")
    }
}
