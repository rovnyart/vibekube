import Foundation

struct InMemoryUserPreferences: UserPreferencesProviding {
    var selectedContextID: String?
    var selectedResourceID: String?
    var selectedNamespaceByContextID: [String: String] = [:]
    var diagnosticsFileLoggingEnabled = false
    var diagnosticsIncludeClusterNames = false
    var diagnosticsRetentionDays = 7
    var podLogLineLimit = 5_000
    var secretRevealRequiresConfirmation = true
    var defaultNamespaceBehavior: DefaultNamespaceBehavior = .allNamespaces
    var resourceWatchesEnabled = true
    var kubeconfigPathOverride: String?
}
