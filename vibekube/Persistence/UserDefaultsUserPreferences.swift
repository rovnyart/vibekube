import Foundation

struct UserDefaultsUserPreferences: UserPreferencesProviding {
    private enum Key {
        static let selectedContextID = "vibekube.selectedContextID"
        static let selectedResourceID = "vibekube.selectedResourceID"
        static let selectedNamespaceByContextID = "vibekube.selectedNamespaceByContextID"
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
