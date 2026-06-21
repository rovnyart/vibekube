import Foundation

enum MutationConfirmationPolicy {
    static func deleteConfirmationPhrase(resourceKind: String, resourceName: String) -> String {
        resourceKind == "Namespace" ? "delete \(resourceName)" : resourceName
    }
}
