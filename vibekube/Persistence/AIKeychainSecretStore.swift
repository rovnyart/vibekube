import Foundation
import Security

protocol AISecretStoring {
    func loadSecrets() throws -> AIProviderSecrets
    func saveSecrets(_ secrets: AIProviderSecrets) throws
    func deleteSecrets() throws
}

enum AIKeychainSecretStoreError: LocalizedError {
    case encodeFailed
    case decodeFailed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodeFailed:
            "Could not encode AI secrets."
        case .decodeFailed:
            "Could not decode AI secrets from Keychain."
        case .keychain(let status):
            "Keychain error \(status)."
        }
    }
}

struct AIKeychainSecretStore: AISecretStoring {
    private let service = "tech.vibekube.ai"
    private let account = "default-provider"

    func loadSecrets() throws -> AIProviderSecrets {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return .empty
        }
        guard status == errSecSuccess else {
            throw AIKeychainSecretStoreError.keychain(status)
        }
        guard let data = item as? Data else {
            throw AIKeychainSecretStoreError.decodeFailed
        }

        do {
            return try JSONDecoder().decode(AIProviderSecrets.self, from: data)
        } catch {
            throw AIKeychainSecretStoreError.decodeFailed
        }
    }

    func saveSecrets(_ secrets: AIProviderSecrets) throws {
        guard let data = try? JSONEncoder().encode(secrets) else {
            throw AIKeychainSecretStoreError.encodeFailed
        }

        var query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AIKeychainSecretStoreError.keychain(updateStatus)
        }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AIKeychainSecretStoreError.keychain(addStatus)
        }
    }

    func deleteSecrets() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIKeychainSecretStoreError.keychain(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct InMemoryAISecretStore: AISecretStoring {
    private final class Box {
        var secrets: AIProviderSecrets = .empty
    }

    private let box = Box()

    func loadSecrets() throws -> AIProviderSecrets {
        box.secrets
    }

    func saveSecrets(_ secrets: AIProviderSecrets) throws {
        box.secrets = secrets
    }

    func deleteSecrets() throws {
        box.secrets = .empty
    }
}
