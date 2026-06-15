import SwiftUI

struct ResourcePlaceholderView: View {
    let item: ResourceNavigationItem

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: item.systemImage)
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(item.title)
                    .font(.title2.weight(.semibold))
                Text("No data loaded")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("resource.placeholder.\(item.id)")
    }
}
