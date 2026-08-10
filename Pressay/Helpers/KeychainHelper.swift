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
    private let apiKeyCacheLock = NSLock()
    private var apiKeyCacheLoaded = false
    private var cachedAPIKey: String?

    init(service: String = Constants.keychainService) {
        self.service = service
    }

    func save(apiKey: String) -> Bool {
        guard let data = apiKey.data(using: .utf8) else { return false }
        return save(data: data, account: Constants.keychainAPIKeyAccount)
    }

    func getAPIKey() -> String? {
        apiKeyCacheLock.lock()
        if apiKeyCacheLoaded {
            let value = cachedAPIKey
            apiKeyCacheLock.unlock()
            return value
        }
        apiKeyCacheLock.unlock()

        let loadedValue = data(account: Constants.keychainAPIKeyAccount)
            .flatMap { String(data: $0, encoding: .utf8) }

        apiKeyCacheLock.lock()
        if !apiKeyCacheLoaded {
            cachedAPIKey = loadedValue
            apiKeyCacheLoaded = true
        }
        let value = cachedAPIKey
        apiKeyCacheLock.unlock()
        return value
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
        let saved = SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        if account == Constants.keychainAPIKeyAccount {
            updateCachedAPIKey(
                saved ? String(data: data, encoding: .utf8) : nil
            )
        }
        return saved
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
        let deleted = status == errSecSuccess || status == errSecItemNotFound
        if deleted, account == Constants.keychainAPIKeyAccount {
            updateCachedAPIKey(nil)
        }
        return deleted
    }

    var hasAPIKey: Bool {
        getAPIKey() != nil
    }

    private func updateCachedAPIKey(_ value: String?) {
        apiKeyCacheLock.lock()
        cachedAPIKey = value
        apiKeyCacheLoaded = true
        apiKeyCacheLock.unlock()
    }
}
