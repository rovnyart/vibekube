import Foundation

struct UserDefaultsUserPreferences: UserPreferencesProviding {
    private enum Key {
        static let selectedContextID = "vibekube.selectedContextID"
        static let selectedResourceID = "vibekube.selectedResourceID"
        static let selectedNamespaceByContextID = "vibekube.selectedNamespaceByContextID"
        static let diagnosticsFileLoggingEnabled = "vibekube.diagnostics.fileLoggingEnabled"
        static let diagnosticsIncludeClusterNames = "vibekube.diagnostics.includeClusterNames"
        static let diagnosticsRetentionDays = "vibekube.diagnostics.retentionDays"
        static let podLogLineLimit = "vibekube.logs.lineLimit"
        static let secretRevealRequiresConfirmation = "vibekube.secrets.revealRequiresConfirmation"
        static let defaultNamespaceBehavior = "vibekube.namespace.defaultBehavior"
        static let resourceWatchesEnabled = "vibekube.watches.enabled"
        static let kubeconfigPathOverride = "vibekube.kubeconfig.pathOverride"
        static let tableDensity = "vibekube.table.density"
        static let appAppearance = "vibekube.appearance"

        static let all = [
            selectedContextID,
            selectedResourceID,
            selectedNamespaceByContextID,
            diagnosticsFileLoggingEnabled,
            diagnosticsIncludeClusterNames,
            diagnosticsRetentionDays,
            podLogLineLimit,
            secretRevealRequiresConfirmation,
            defaultNamespaceBehavior,
            resourceWatchesEnabled,
            kubeconfigPathOverride,
            tableDensity,
            appAppearance
        ]
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

    var podLogLineLimit: Int {
        get {
            let value = defaults.integer(forKey: Key.podLogLineLimit)
            return value > 0 ? value : 5_000
        }
        set {
            defaults.set(max(500, min(newValue, 50_000)), forKey: Key.podLogLineLimit)
        }
    }

    var secretRevealRequiresConfirmation: Bool {
        get {
            guard defaults.object(forKey: Key.secretRevealRequiresConfirmation) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.secretRevealRequiresConfirmation)
        }
        set {
            defaults.set(newValue, forKey: Key.secretRevealRequiresConfirmation)
        }
    }

    var defaultNamespaceBehavior: DefaultNamespaceBehavior {
        get {
            guard let rawValue = defaults.string(forKey: Key.defaultNamespaceBehavior),
                  let behavior = DefaultNamespaceBehavior(rawValue: rawValue) else {
                return .allNamespaces
            }
            return behavior
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.defaultNamespaceBehavior)
        }
    }

    var resourceWatchesEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.resourceWatchesEnabled) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.resourceWatchesEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.resourceWatchesEnabled)
        }
    }

    var kubeconfigPathOverride: String? {
        get {
            guard let value = defaults.string(forKey: Key.kubeconfigPathOverride),
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return value
        }
        set {
            let normalized = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.setOrRemove(normalized?.isEmpty == false ? normalized : nil, forKey: Key.kubeconfigPathOverride)
        }
    }

    var tableDensity: TableDensity {
        get {
            guard let rawValue = defaults.string(forKey: Key.tableDensity),
                  let density = TableDensity(rawValue: rawValue) else {
                return .comfortable
            }
            return density
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.tableDensity)
        }
    }

    var appAppearance: AppAppearance {
        get {
            guard let rawValue = defaults.string(forKey: Key.appAppearance),
                  let appearance = AppAppearance(rawValue: rawValue) else {
                return .system
            }
            return appearance
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.appAppearance)
        }
    }

    func resetLocalPreferences() {
        for key in Key.all {
            defaults.removeObject(forKey: key)
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
