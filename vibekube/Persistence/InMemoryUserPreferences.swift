import Foundation

struct InMemoryUserPreferences: UserPreferencesProviding {
    var selectedContextID: String?
    var selectedNamespaceByContextID: [String: String] = [:]
}
