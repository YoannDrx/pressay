import Foundation

struct LegacyIdentitySource {
    let identifier: String
    let defaults: UserDefaults?
    let keychain: KeychainStoring
}

/// Creates the one-time proof that this Mac ran Pressay before the commercial
/// paywall. The opaque value can later be claimed by an authenticated account;
/// it never contains user data and is never regenerated after a successful
/// write.
struct FoundingEligibilityService {
    private let keychain: KeychainStoring
    private let generateMarker: () -> Data

    init(
        keychain: KeychainStoring = KeychainHelper.shared,
        generateMarker: @escaping () -> Data = {
            Data(UUID().uuidString.utf8)
        }
    ) {
        self.keychain = keychain
        self.generateMarker = generateMarker
    }

    @discardableResult
    func createIfNeeded() -> Bool {
        if keychain.data(account: Constants.keychainFoundingEligibilityAccount) != nil {
            return true
        }

        let marker = generateMarker()
        guard !marker.isEmpty,
              keychain.save(
                  data: marker,
                  account: Constants.keychainFoundingEligibilityAccount
              ) else {
            return false
        }
        return keychain.data(account: Constants.keychainFoundingEligibilityAccount) == marker
    }
}

struct AppMigrationService {
    private let defaults: UserDefaults
    private let currentKeychain: KeychainStoring
    private let legacySources: [LegacyIdentitySource]
    private let fileManager: FileManager
    private let applicationSupportRoot: URL

    init(
        defaults: UserDefaults = .standard,
        currentKeychain: KeychainStoring = KeychainHelper.shared,
        legacySources: [LegacyIdentitySource]? = nil,
        fileManager: FileManager = .default,
        applicationSupportRoot: URL? = nil
    ) {
        self.defaults = defaults
        self.currentKeychain = currentKeychain
        self.legacySources = legacySources ?? Constants.legacyBundleIdentifiers.map {
            LegacyIdentitySource(
                identifier: $0,
                defaults: UserDefaults(suiteName: $0),
                keychain: KeychainHelper(service: $0)
            )
        }
        self.fileManager = fileManager
        self.applicationSupportRoot = applicationSupportRoot
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    @discardableResult
    func runIfNeeded() -> Bool {
        guard !defaults.bool(forKey: Constants.identityMigrationCompletedKey) else {
            return true
        }

        migratePreferences()

        let accounts = [
            Constants.keychainAPIKeyAccount,
            Constants.keychainHistoryKeyAccount
        ]
        let didMigrateKeychain = accounts.allSatisfy(migrateKeychainItem(account:))
        let didMigrateApplicationSupport = migrateApplicationSupport()

        guard didMigrateKeychain, didMigrateApplicationSupport else { return false }
        defaults.set(true, forKey: Constants.identityMigrationCompletedKey)
        return true
    }

    private func migratePreferences() {
        for key in Constants.migratedPreferenceKeys
        where defaults.object(forKey: key) == nil {
            for source in legacySources {
                guard let value = source.defaults?.object(forKey: key) else { continue }
                defaults.set(value, forKey: key)
                break
            }
        }
    }

    private func migrateKeychainItem(account: String) -> Bool {
        if let currentData = currentKeychain.data(account: account) {
            for source in legacySources {
                if let legacyData = source.keychain.data(account: account),
                   currentData == legacyData,
                   !source.keychain.delete(account: account) {
                    return false
                }
            }
            return true
        }

        guard let source = legacySources.first(where: {
            $0.keychain.data(account: account) != nil
        }), let legacyData = source.keychain.data(account: account) else {
            return true
        }
        guard currentKeychain.save(data: legacyData, account: account),
              currentKeychain.data(account: account) == legacyData else {
            return false
        }

        guard source.keychain.delete(account: account) else { return false }
        for lowerPrioritySource in legacySources {
            if lowerPrioritySource.identifier == source.identifier { continue }
            if lowerPrioritySource.keychain.data(account: account) == legacyData,
               !lowerPrioritySource.keychain.delete(account: account) {
                return false
            }
        }
        return true
    }

    private func migrateApplicationSupport() -> Bool {
        let legacyDirectory = applicationSupportRoot.appendingPathComponent(
            Constants.legacyApplicationSupportDirectoryName,
            isDirectory: true
        )
        let currentDirectory = applicationSupportRoot.appendingPathComponent(
            Constants.applicationSupportDirectoryName,
            isDirectory: true
        )

        guard fileManager.fileExists(atPath: legacyDirectory.path) else { return true }

        if !fileManager.fileExists(atPath: currentDirectory.path) {
            do {
                try fileManager.createDirectory(
                    at: applicationSupportRoot,
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: legacyDirectory, to: currentDirectory)
                return fileManager.fileExists(atPath: currentDirectory.path)
                    && !fileManager.fileExists(atPath: legacyDirectory.path)
            } catch {
                return false
            }
        }

        for filename in ["history.enc", "history.json"] {
            let legacyFile = legacyDirectory.appendingPathComponent(filename)
            let currentFile = currentDirectory.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: legacyFile.path) else { continue }

            if fileManager.fileExists(atPath: currentFile.path) {
                if (try? Data(contentsOf: legacyFile)) == (try? Data(contentsOf: currentFile)) {
                    try? fileManager.removeItem(at: legacyFile)
                }
                continue
            }

            do {
                try fileManager.copyItem(at: legacyFile, to: currentFile)
                guard try Data(contentsOf: currentFile) == Data(contentsOf: legacyFile) else {
                    try? fileManager.removeItem(at: currentFile)
                    return false
                }
                try fileManager.removeItem(at: legacyFile)
            } catch {
                return false
            }
        }

        if let remaining = try? fileManager.contentsOfDirectory(
            at: legacyDirectory,
            includingPropertiesForKeys: nil
        ), remaining.isEmpty {
            try? fileManager.removeItem(at: legacyDirectory)
        }
        return true
    }
}
