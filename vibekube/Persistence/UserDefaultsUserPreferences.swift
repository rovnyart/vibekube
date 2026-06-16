import Foundation

struct UserDefaultsUserPreferences: UserPreferencesProviding {
    private enum Key {
        static let selectedContextID = "vibekube.selectedContextID"
        static let selectedResourceID = "vibekube.selectedResourceID"
        static let selectedNamespaceByContextID = "vibekube.selectedNamespaceByContextID"
        static let diagnosticsFileLoggingEnabled = "vibekube.diagnostics.fileLoggingEnabled"
        static let diagnosticsIncludeClusterNames = "vibekube.diagnostics.includeClusterNames"
        static let diagnosticsRetentionDays = "vibekube.diagnostics.retentionDays"
    }

    var defaults: UserDefaults = .standard

    var selectedContextID: String? {
        get { defaults.string(forKey: Key.selectedContextID) }
        set { defaults.setOrRemove(newValue, forKey: Key.selectedContextID) }
    }

    var selectedResourceID: String? {
        get { defaults.string(forKey: Key.selectedResourceID) }
        set { defaults.setOrRemove(newValue, forKey: Key.selectedResourceID) }
    }

    var selectedNamespaceByContextID: [String: String] {
        get {
            defaults.dictionary(forKey: Key.selectedNamespaceByContextID) as? [String: String] ?? [:]
        }
        set {
            defaults.set(newValue, forKey: Key.selectedNamespaceByContextID)
        }
    }

    var diagnosticsFileLoggingEnabled: Bool {
        get { defaults.bool(forKey: Key.diagnosticsFileLoggingEnabled) }
        set { defaults.set(newValue, forKey: Key.diagnosticsFileLoggingEnabled) }
    }

    var diagnosticsIncludeClusterNames: Bool {
        get { defaults.bool(forKey: Key.diagnosticsIncludeClusterNames) }
        set { defaults.set(newValue, forKey: Key.diagnosticsIncludeClusterNames) }
    }

    var diagnosticsRetentionDays: Int {
        get {
            let value = defaults.integer(forKey: Key.diagnosticsRetentionDays)
            return value > 0 ? value : 7
        }
        set {
            defaults.set(max(1, min(newValue, 30)), forKey: Key.diagnosticsRetentionDays)
        }
    }
}

private extension UserDefaults {
    func setOrRemove(_ value: String?, forKey key: String) {
        if let value {
            set(value, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}
