import Foundation
import Security

protocol KeychainStoring {
    func save(data: Data, account: String) -> Bool
    func data(account: String) -> Data?
    func delete(account: String) -> Bool
}

final class KeychainHelper: KeychainStoring {
    static let shared = KeychainHelper()

    private let service: String

    init(service: String = Constants.keychainService) {
        self.service = service
    }

    func save(apiKey: String) -> Bool {
        guard let data = apiKey.data(using: .utf8) else { return false }
        return save(data: data, account: Constants.keychainAPIKeyAccount)
    }

    func getAPIKey() -> String? {
        guard let data = data(account: Constants.keychainAPIKeyAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(data: Data, account: String) -> Bool {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func data(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    func delete() -> Bool {
        delete(account: Constants.keychainAPIKeyAccount)
    }

    @discardableResult
    func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    var hasAPIKey: Bool {
        getAPIKey() != nil
    }
}
