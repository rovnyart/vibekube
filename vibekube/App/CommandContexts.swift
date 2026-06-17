import SwiftUI

struct ResourceDetailCommandContext {
    var title: String
    var isLoaded: Bool
    var selectPanel: (ResourceDetailPanel) -> Void
    var copyIdentity: () -> Void
    var copyYAML: () -> Void
    var saveYAML: () -> Void
}

private struct ResourceDetailCommandContextKey: FocusedValueKey {
    typealias Value = ResourceDetailCommandContext
}

extension FocusedValues {
    var resourceDetailCommandContext: ResourceDetailCommandContext? {
        get { self[ResourceDetailCommandContextKey.self] }
        set { self[ResourceDetailCommandContextKey.self] = newValue }
    }
}
