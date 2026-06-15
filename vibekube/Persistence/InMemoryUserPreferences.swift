import Foundation

struct InMemoryUserPreferences: UserPreferencesProviding {
    var selectedContextID: String?
    var selectedResourceID: String?
    var selectedNamespaceByContextID: [String: String] = [:]
}
