const BYOK_SERVICE: &str = "app.pressay.desktop.byok";
const HISTORY_SERVICE: &str = "app.pressay.desktop.history";
const HISTORY_MASTER_KEY_ACCOUNT: &str = "master-key-v1";
const CLOUD_SERVICE: &str = "app.pressay.desktop.cloud";
const CLOUD_BEARER_ACCOUNT: &str = "bearer-token-v1";
const CLOUD_OAUTH_TOKEN_SET_ACCOUNT: &str = "oauth-token-set-v1";
#[cfg(any(target_os = "macos", windows))]
const CLOUD_OAUTH_MIGRATION_DISABLED_ACCOUNT: &str = "oauth-legacy-migration-disabled-v1";
#[cfg_attr(test, allow(dead_code))]
const CLOUD_PENDING_OAUTH_ACCOUNT: &str = "pending-oauth-v1";
const CLOUD_ENTITLEMENT_ACCOUNT: &str = "entitlement-snapshot-v1";
const CLOUD_SYNC_DEVICE_KEY_PREFIX: &str = "sync-device-private-key-v1";
const CLOUD_SYNC_ACCOUNT_KEY_PREFIX: &str = "sync-account-key-v1";

fn cloud_sync_account(prefix: &str, account_id: &str) -> Result<String, String> {
    let account_id = uuid::Uuid::parse_str(account_id)
        .map_err(|_| "Invalid Cloud account identifier".to_string())?;
    Ok(format!("{prefix}:{account_id}"))
}

fn validate_provider_id(provider_id: &str) -> Result<(), String> {
    if provider_id.is_empty()
        || !provider_id
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || matches!(character, '_' | '-'))
    {
        return Err("Invalid provider identifier".to_string());
    }

    Ok(())
}

fn validate_cloud_bearer_token(token: &str) -> Result<(), String> {
    if !(32..=4096).contains(&token.len())
        || !token
            .bytes()
            .all(|byte| byte.is_ascii_graphic() && !byte.is_ascii_whitespace())
    {
        return Err("The Cloud session token has an invalid format".to_string());
    }
    Ok(())
}

fn validate_cloud_oauth_token_set(token_set: &str) -> Result<(), String> {
    if !(64..=16_384).contains(&token_set.len()) || token_set.chars().any(char::is_control) {
        return Err("The Cloud OAuth session has an invalid format".to_string());
    }
    Ok(())
}

#[cfg_attr(test, allow(dead_code))]
fn validate_pending_cloud_oauth(pending: &str) -> Result<(), String> {
    if !(96..=2048).contains(&pending.len()) || pending.chars().any(char::is_control) {
        return Err("The pending Cloud OAuth request has an invalid format".to_string());
    }
    Ok(())
}

fn validate_cloud_entitlement_snapshot(token: &str) -> Result<(), String> {
    if !(64..=8192).contains(&token.len())
        || token.matches('.').count() != 2
        || !token
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.'))
    {
        return Err("The Cloud entitlement snapshot has an invalid format".to_string());
    }
    Ok(())
}

/// Windows has no Keychain equivalent that holds a 16 KiB OAuth token set
/// (Credential Manager caps a blob at 2,560 bytes), so each secret is sealed
/// with DPAPI for the current Windows user and written to its own file under
/// `%LOCALAPPDATA%`. Another user, or the same files copied to another machine,
/// cannot unseal them.
#[cfg(windows)]
mod windows_store {
    use sha2::{Digest, Sha256};
    use std::io::ErrorKind;
    use std::path::PathBuf;
    use windows::Win32::Foundation::{LocalFree, HLOCAL};
    use windows::Win32::Security::Cryptography::{
        CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
    };

    const ENTROPY: &[u8] = b"app.pressay.desktop/secrets/v1";

    pub enum Error {
        NoEntry,
        Failed,
    }

    pub struct Entry {
        path: PathBuf,
    }

    impl Entry {
        pub fn new(service: &str, account: &str) -> Result<Self, Error> {
            let base = std::env::var_os("LOCALAPPDATA")
                .map(PathBuf::from)
                .ok_or(Error::Failed)?;
            // Account names contain `:`, which NTFS file names reject.
            let mut digest = Sha256::new();
            digest.update(service.as_bytes());
            digest.update([0]);
            digest.update(account.as_bytes());
            let name: String = digest
                .finalize()
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect();
            Ok(Self {
                path: base
                    .join("app.pressay.desktop")
                    .join("secrets")
                    .join(format!("{name}.bin")),
            })
        }

        pub fn get_password(&self) -> Result<String, Error> {
            String::from_utf8(self.get_secret()?).map_err(|_| Error::Failed)
        }

        pub fn set_password(&self, password: &str) -> Result<(), Error> {
            self.set_secret(password.as_bytes())
        }

        pub fn get_secret(&self) -> Result<Vec<u8>, Error> {
            let sealed = match std::fs::read(&self.path) {
                Ok(sealed) => sealed,
                Err(error) if error.kind() == ErrorKind::NotFound => return Err(Error::NoEntry),
                Err(_) => return Err(Error::Failed),
            };
            unseal(&sealed)
        }

        pub fn set_secret(&self, secret: &[u8]) -> Result<(), Error> {
            let sealed = seal(secret)?;
            let directory = self.path.parent().ok_or(Error::Failed)?;
            std::fs::create_dir_all(directory).map_err(|_| Error::Failed)?;
            // Write then rename so an interrupted save never leaves a torn file.
            let staging = self.path.with_extension("tmp");
            std::fs::write(&staging, sealed).map_err(|_| Error::Failed)?;
            std::fs::rename(&staging, &self.path).map_err(|_| {
                let _ = std::fs::remove_file(&staging);
                Error::Failed
            })
        }

        pub fn delete_credential(&self) -> Result<(), Error> {
            match std::fs::remove_file(&self.path) {
                Ok(()) => Ok(()),
                Err(error) if error.kind() == ErrorKind::NotFound => Err(Error::NoEntry),
                Err(_) => Err(Error::Failed),
            }
        }
    }

    fn blob(bytes: &[u8]) -> CRYPT_INTEGER_BLOB {
        CRYPT_INTEGER_BLOB {
            cbData: bytes.len() as u32,
            pbData: bytes.as_ptr() as *mut u8,
        }
    }

    /// Copies DPAPI's LocalAlloc'd output and frees it.
    fn take(output: CRYPT_INTEGER_BLOB) -> Vec<u8> {
        if output.pbData.is_null() {
            return Vec::new();
        }
        // SAFETY: DPAPI returned `cbData` initialised bytes at `pbData`.
        let bytes =
            unsafe { std::slice::from_raw_parts(output.pbData, output.cbData as usize) }.to_vec();
        // SAFETY: the buffer was allocated by DPAPI with LocalAlloc.
        unsafe {
            let _ = LocalFree(Some(HLOCAL(output.pbData.cast())));
        }
        bytes
    }

    fn seal(secret: &[u8]) -> Result<Vec<u8>, Error> {
        let input = blob(secret);
        let entropy = blob(ENTROPY);
        let mut output = CRYPT_INTEGER_BLOB::default();
        // SAFETY: every pointer refers to a live buffer for the whole call.
        unsafe {
            CryptProtectData(
                &input,
                windows::core::PCWSTR::null(),
                Some(&entropy),
                None,
                None,
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output,
            )
        }
        .map_err(|_| Error::Failed)?;
        Ok(take(output))
    }

    fn unseal(sealed: &[u8]) -> Result<Vec<u8>, Error> {
        let input = blob(sealed);
        let entropy = blob(ENTROPY);
        let mut output = CRYPT_INTEGER_BLOB::default();
        // SAFETY: every pointer refers to a live buffer for the whole call.
        unsafe {
            CryptUnprotectData(
                &input,
                None,
                Some(&entropy),
                None,
                None,
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output,
            )
        }
        .map_err(|_| Error::Failed)?;
        Ok(take(output))
    }

    #[cfg(test)]
    mod tests {
        use super::Entry;

        #[test]
        fn sealed_secrets_round_trip_and_delete() {
            let account = format!("test:{}", uuid::Uuid::new_v4());
            let entry = Entry::new("app.pressay.desktop.test", &account)
                .ok()
                .unwrap();
            let large = "x".repeat(16_384);
            assert!(entry.set_password(&large).is_ok());
            assert_eq!(entry.get_password().ok().as_deref(), Some(large.as_str()));
            let on_disk = std::fs::read(&entry.path).unwrap();
            assert!(!on_disk
                .windows(64)
                .any(|window| window == &large.as_bytes()[..64]));
            assert!(entry.delete_credential().is_ok());
            assert!(matches!(entry.get_secret(), Err(super::Error::NoEntry)));
            assert!(matches!(
                entry.delete_credential(),
                Err(super::Error::NoEntry)
            ));
        }
    }
}

#[cfg(any(target_os = "macos", windows))]
mod platform {
    #[cfg(windows)]
    use super::windows_store::{Entry, Error};
    use super::{
        cloud_sync_account, validate_cloud_bearer_token, validate_cloud_entitlement_snapshot,
        validate_provider_id, BYOK_SERVICE, CLOUD_BEARER_ACCOUNT, CLOUD_ENTITLEMENT_ACCOUNT,
        CLOUD_OAUTH_MIGRATION_DISABLED_ACCOUNT, CLOUD_OAUTH_TOKEN_SET_ACCOUNT,
        CLOUD_PENDING_OAUTH_ACCOUNT, CLOUD_SERVICE, CLOUD_SYNC_ACCOUNT_KEY_PREFIX,
        CLOUD_SYNC_DEVICE_KEY_PREFIX, HISTORY_MASTER_KEY_ACCOUNT, HISTORY_SERVICE,
    };
    #[cfg(target_os = "macos")]
    use keyring_core::{Entry, Error};
    #[cfg(target_os = "macos")]
    use std::sync::OnceLock;

    #[cfg(target_os = "macos")]
    const SECURE_STORE: &str = "the macOS Keychain";
    #[cfg(windows)]
    const SECURE_STORE: &str = "Windows secure storage";

    #[cfg(target_os = "macos")]
    static STORE_INITIALIZED: OnceLock<Result<(), String>> = OnceLock::new();

    #[cfg(target_os = "macos")]
    fn initialize_store() -> Result<(), String> {
        STORE_INITIALIZED
            .get_or_init(|| {
                if std::env::var_os("APP_SANDBOX_CONTAINER_ID").is_some() {
                    // The data-protection Keychain stores items in the first
                    // `keychain-access-groups` entry of Entitlements.AppStore.plist,
                    // `G9WFV7HNV6.fr.yodev.pressay`; no group is passed here so
                    // the entitlement stays the single source of truth.
                    let store = apple_native_keyring_store::protected::Store::new()
                        .map_err(|_| "The macOS Keychain is unavailable".to_string())?;
                    keyring_core::set_default_store(store);
                } else {
                    let store = apple_native_keyring_store::keychain::Store::new()
                        .map_err(|_| "The macOS Keychain is unavailable".to_string())?;
                    keyring_core::set_default_store(store);
                }
                Ok(())
            })
            .clone()
    }

    #[cfg(target_os = "macos")]
    fn entry(service: &str, account: &str) -> Result<Entry, String> {
        initialize_store()?;
        Entry::new(service, account).map_err(|_| "Unable to access the macOS Keychain".to_string())
    }

    #[cfg(windows)]
    fn entry(service: &str, account: &str) -> Result<Entry, String> {
        Entry::new(service, account).map_err(|_| format!("Unable to access {SECURE_STORE}"))
    }

    pub fn get_provider_api_key(provider_id: &str) -> Result<Option<String>, String> {
        validate_provider_id(provider_id)?;
        match entry(BYOK_SERVICE, provider_id)?.get_password() {
            Ok(secret) => Ok(Some(secret)),
            Err(Error::NoEntry) => Ok(None),
            Err(_) => Err(format!("Unable to read the API key from {SECURE_STORE}")),
        }
    }

    pub fn set_provider_api_key(provider_id: &str, api_key: &str) -> Result<(), String> {
        validate_provider_id(provider_id)?;
        let entry = entry(BYOK_SERVICE, provider_id)?;
        if api_key.is_empty() {
            return match entry.delete_credential() {
                Ok(()) | Err(Error::NoEntry) => Ok(()),
                Err(_) => Err(format!("Unable to delete the API key from {SECURE_STORE}")),
            };
        }

        entry
            .set_password(api_key)
            .map_err(|_| format!("Unable to save the API key in {SECURE_STORE}"))
    }

    /// Copies the OpenAI key from the former native Pressay/Whisper Keychain
    /// services. The legacy credential is intentionally retained so an older
    /// installed build keeps working and the migration remains reversible.
    pub fn migrate_legacy_openai_api_key() -> Result<bool, String> {
        if get_provider_api_key("openai")?.is_some() {
            return Ok(false);
        }
        for service in ["fr.yodev.pressay", "fr.yodev.whisper", "com.hyrak.whisper"] {
            match entry(service, "openai-api-key")?.get_password() {
                Ok(secret) if !secret.trim().is_empty() => {
                    set_provider_api_key("openai", &secret)?;
                    return Ok(true);
                }
                Ok(_) | Err(Error::NoEntry) => {}
                Err(_) => {
                    return Err(format!(
                        "Unable to read the legacy API key from {SECURE_STORE}"
                    ))
                }
            }
        }
        Ok(false)
    }

    /// Copies the former native app OAuth token set into the current service.
    /// The source entry is retained so downgrading remains possible.
    pub fn migrate_legacy_cloud_oauth_token_set() -> Result<bool, String> {
        match entry(CLOUD_SERVICE, CLOUD_OAUTH_MIGRATION_DISABLED_ACCOUNT)?.get_password() {
            Ok(_) => return Ok(false),
            Err(Error::NoEntry) => {}
            Err(_) => {
                return Err(format!(
                    "Unable to read the Cloud migration state from {SECURE_STORE}"
                ))
            }
        }
        if get_cloud_oauth_token_set()?.is_some() {
            return Ok(false);
        }
        match entry("fr.yodev.pressay", "pressay-account-oauth-tokens-v1")?.get_password() {
            Ok(token_set) => {
                super::validate_cloud_oauth_token_set(&token_set)?;
                set_cloud_oauth_token_set(&token_set)?;
                Ok(true)
            }
            Err(Error::NoEntry) => Ok(false),
            Err(_) => Err(format!(
                "Unable to read the legacy Cloud OAuth session from {SECURE_STORE}"
            )),
        }
    }

    pub fn get_history_master_key() -> Result<Option<[u8; 32]>, String> {
        match entry(HISTORY_SERVICE, HISTORY_MASTER_KEY_ACCOUNT)?.get_secret() {
            Ok(secret) => secret
                .try_into()
                .map(Some)
                .map_err(|_| "The history encryption key has an invalid format".to_string()),
            Err(Error::NoEntry) => Ok(None),
            Err(_) => Err(format!(
                "Unable to read the history key from {SECURE_STORE}"
            )),
        }
    }

    pub fn set_history_master_key(key: &[u8; 32]) -> Result<(), String> {
        entry(HISTORY_SERVICE, HISTORY_MASTER_KEY_ACCOUNT)?
            .set_secret(key)
            .map_err(|_| format!("Unable to save the history key in {SECURE_STORE}"))
    }

    pub fn delete_history_master_key() -> Result<(), String> {
        match entry(HISTORY_SERVICE, HISTORY_MASTER_KEY_ACCOUNT)?.delete_credential() {
            Ok(()) | Err(Error::NoEntry) => Ok(()),
            Err(_) => Err(format!(
                "Unable to delete the history key from {SECURE_STORE}"
            )),
        }
    }

    pub fn get_cloud_bearer_token() -> Result<Option<String>, String> {
        match entry(CLOUD_SERVICE, CLOUD_BEARER_ACCOUNT)?.get_password() {
            Ok(token) => {
                validate_cloud_bearer_token(&token)?;
                Ok(Some(token))
            }
            Err(Error::NoEntry) => Ok(None),
            Err(_) => Err(format!(
                "Unable to read the Cloud session from {SECURE_STORE}"
            )),
        }
    }

    pub fn set_cloud_bearer_token(token: &str) -> Result<(), String> {
        validate_cloud_bearer_token(token)?;
        entry(CLOUD_SERVICE, CLOUD_BEARER_ACCOUNT)?
            .set_password(token)
            .map_err(|_| format!("Unable to save the Cloud session in {SECURE_STORE}"))
    }

    pub fn delete_cloud_bearer_token() -> Result<(), String> {
        match entry(CLOUD_SERVICE, CLOUD_BEARER_ACCOUNT)?.delete_credential() {
            Ok(()) | Err(Error::NoEntry) => Ok(()),
            Err(_) => Err(format!(
                "Unable to delete the Cloud session from {SECURE_STORE}"
            )),
        }
    }

    pub fn get_cloud_oauth_token_set() -> Result<Option<String>, String> {
        match entry(CLOUD_SERVICE, CLOUD_OAUTH_TOKEN_SET_ACCOUNT)?.get_password() {
            Ok(token_set) => {
                super::validate_cloud_oauth_token_set(&token_set)?;
                Ok(Some(token_set))
            }
            Err(Error::NoEntry) => Ok(None),
            Err(_) => Err(format!(
                "Unable to read the Cloud OAuth session from {SECURE_STORE}"
            )),
        }
    }

    pub fn set_cloud_oauth_token_set(token_set: &str) -> Result<(), String> {
        super::validate_cloud_oauth_token_set(token_set)?;
        entry(CLOUD_SERVICE, CLOUD_OAUTH_TOKEN_SET_ACCOUNT)?
            .set_password(token_set)
            .map_err(|_| format!("Unable to save the Cloud OAuth session in {SECURE_STORE}"))
    }

    pub fn delete_cloud_oauth_token_set() -> Result<(), String> {
        // Keep the old app's credential for downgrades, but never silently
        // import it again after this app has explicitly signed out. Write this
        // first so an interrupted cleanup cannot resurrect the old session.
        entry(CLOUD_SERVICE, CLOUD_OAUTH_MIGRATION_DISABLED_ACCOUNT)?
            .set_password("disabled")
            .map_err(|_| format!("Unable to save the Cloud migration state in {SECURE_STORE}"))?;
        match entry(CLOUD_SERVICE, CLOUD_OAUTH_TOKEN_SET_ACCOUNT)?.delete_credential() {
            Ok(()) | Err(Error::NoEntry) => Ok(()),
            Err(_) => Err(format!(
                "Unable to delete the Cloud OAuth session from {SECURE_STORE}"
            )),
        }
    }

    #[cfg_attr(test, allow(dead_code))]
    pub fn get_pending_cloud_oauth() -> Result<Option<String>, String> {
        match entry(CLOUD_SERVICE, CLOUD_PENDING_OAUTH_ACCOUNT)?.get_password() {
            Ok(pending) => {
                super::validate_pending_cloud_oauth(&pending)?;
                Ok(Some(pending))
            }
            Err(Error::NoEntry) => Ok(None),
            Err(_) => Err(format!(
                "Unable to read the pending Cloud OAuth request from {SECURE_STORE}"
            )),
        }
    }

    #[cfg_attr(test, allow(dead_code))]
    pub fn set_pending_cloud_oauth(pending: &str) -> Result<(), String> {
        super::validate_pending_cloud_oauth(pending)?;
        entry(CLOUD_SERVICE, CLOUD_PENDING_OAUTH_ACCOUNT)?
            .set_password(pending)
            .map_err(|_| {
                format!("Unable to save the pending Cloud OAuth request in {SECURE_STORE}")
            })
    }

    #[cfg_attr(test, allow(dead_code))]
    pub fn delete_pending_cloud_oauth() -> Result<(), String> {
        match entry(CLOUD_SERVICE, CLOUD_PENDING_OAUTH_ACCOUNT)?.delete_credential() {
            Ok(()) | Err(Error::NoEntry) => Ok(()),
            Err(_) => Err(format!(
                "Unable to delete the pending Cloud OAuth request from {SECURE_STORE}"
            )),
        }
    }

    pub fn get_cloud_entitlement_snapshot() -> Result<Option<String>, String> {
        match entry(CLOUD_SERVICE, CLOUD_ENTITLEMENT_ACCOUNT)?.get_password() {
            Ok(token) => {
                validate_cloud_entitlement_snapshot(&token)?;
                Ok(Some(token))
            }
            Err(Error::NoEntry) => Ok(None),
            Err(_) => Err(format!(
                "Unable to read the Cloud entitlement from {SECURE_STORE}"
            )),
        }
    }

    pub fn set_cloud_entitlement_snapshot(token: &str) -> Result<(), String> {
        validate_cloud_entitlement_snapshot(token)?;
        entry(CLOUD_SERVICE, CLOUD_ENTITLEMENT_ACCOUNT)?
            .set_password(token)
            .map_err(|_| format!("Unable to save the Cloud entitlement in {SECURE_STORE}"))
    }

    pub fn delete_cloud_entitlement_snapshot() -> Result<(), String> {
        match entry(CLOUD_SERVICE, CLOUD_ENTITLEMENT_ACCOUNT)?.delete_credential() {
            Ok(()) | Err(Error::NoEntry) => Ok(()),
            Err(_) => Err(format!(
                "Unable to delete the Cloud entitlement from {SECURE_STORE}"
            )),
        }
    }

    fn get_cloud_sync_key(account: &str) -> Result<Option<[u8; 32]>, String> {
        match entry(CLOUD_SERVICE, account)?.get_secret() {
            Ok(secret) => secret
                .try_into()
                .map(Some)
                .map_err(|_| "The Cloud sync key has an invalid format".to_string()),
            Err(Error::NoEntry) => Ok(None),
            Err(_) => Err(format!(
                "Unable to read the Cloud sync key from {SECURE_STORE}"
            )),
        }
    }

    fn set_cloud_sync_key(account: &str, key: &[u8; 32]) -> Result<(), String> {
        entry(CLOUD_SERVICE, account)?
            .set_secret(key)
            .map_err(|_| format!("Unable to save the Cloud sync key in {SECURE_STORE}"))
    }

    fn delete_cloud_sync_key(account: &str) -> Result<(), String> {
        match entry(CLOUD_SERVICE, account)?.delete_credential() {
            Ok(()) | Err(Error::NoEntry) => Ok(()),
            Err(_) => Err(format!(
                "Unable to delete the Cloud sync key from {SECURE_STORE}"
            )),
        }
    }

    pub fn get_cloud_sync_device_key(account_id: &str) -> Result<Option<[u8; 32]>, String> {
        get_cloud_sync_key(&cloud_sync_account(
            CLOUD_SYNC_DEVICE_KEY_PREFIX,
            account_id,
        )?)
    }

    pub fn set_cloud_sync_device_key(account_id: &str, key: &[u8; 32]) -> Result<(), String> {
        set_cloud_sync_key(
            &cloud_sync_account(CLOUD_SYNC_DEVICE_KEY_PREFIX, account_id)?,
            key,
        )
    }

    pub fn get_cloud_sync_account_key(account_id: &str) -> Result<Option<[u8; 32]>, String> {
        get_cloud_sync_key(&cloud_sync_account(
            CLOUD_SYNC_ACCOUNT_KEY_PREFIX,
            account_id,
        )?)
    }

    pub fn set_cloud_sync_account_key(account_id: &str, key: &[u8; 32]) -> Result<(), String> {
        set_cloud_sync_key(
            &cloud_sync_account(CLOUD_SYNC_ACCOUNT_KEY_PREFIX, account_id)?,
            key,
        )
    }

    pub fn delete_cloud_sync_keys(account_id: &str) -> Result<(), String> {
        delete_cloud_sync_key(&cloud_sync_account(
            CLOUD_SYNC_DEVICE_KEY_PREFIX,
            account_id,
        )?)?;
        delete_cloud_sync_key(&cloud_sync_account(
            CLOUD_SYNC_ACCOUNT_KEY_PREFIX,
            account_id,
        )?)
    }
}

#[cfg(not(any(target_os = "macos", windows)))]
mod platform {
    use super::{
        validate_cloud_bearer_token, validate_cloud_entitlement_snapshot, validate_provider_id,
    };

    pub fn get_provider_api_key(provider_id: &str) -> Result<Option<String>, String> {
        validate_provider_id(provider_id)?;
        Err("Secure BYOK storage is only available in the supported macOS build".to_string())
    }

    pub fn set_provider_api_key(provider_id: &str, _api_key: &str) -> Result<(), String> {
        validate_provider_id(provider_id)?;
        Err("Secure BYOK storage is only available in the supported macOS build".to_string())
    }

    pub fn migrate_legacy_openai_api_key() -> Result<bool, String> {
        Ok(false)
    }

    pub fn migrate_legacy_cloud_oauth_token_set() -> Result<bool, String> {
        Ok(false)
    }

    pub fn get_history_master_key() -> Result<Option<[u8; 32]>, String> {
        Err("Encrypted history is only available in the supported macOS build".to_string())
    }

    pub fn set_history_master_key(_key: &[u8; 32]) -> Result<(), String> {
        Err("Encrypted history is only available in the supported macOS build".to_string())
    }

    pub fn delete_history_master_key() -> Result<(), String> {
        Err("Encrypted history is only available in the supported macOS build".to_string())
    }

    pub fn get_cloud_bearer_token() -> Result<Option<String>, String> {
        Err("Secure Cloud sessions are only available in the supported macOS build".to_string())
    }

    pub fn set_cloud_bearer_token(token: &str) -> Result<(), String> {
        validate_cloud_bearer_token(token)?;
        Err("Secure Cloud sessions are only available in the supported macOS build".to_string())
    }

    pub fn delete_cloud_bearer_token() -> Result<(), String> {
        Err("Secure Cloud sessions are only available in the supported macOS build".to_string())
    }

    pub fn get_cloud_oauth_token_set() -> Result<Option<String>, String> {
        Err(
            "Secure Cloud OAuth sessions are only available in the supported macOS build"
                .to_string(),
        )
    }

    pub fn set_cloud_oauth_token_set(token_set: &str) -> Result<(), String> {
        super::validate_cloud_oauth_token_set(token_set)?;
        Err(
            "Secure Cloud OAuth sessions are only available in the supported macOS build"
                .to_string(),
        )
    }

    pub fn delete_cloud_oauth_token_set() -> Result<(), String> {
        Err(
            "Secure Cloud OAuth sessions are only available in the supported macOS build"
                .to_string(),
        )
    }

    #[cfg_attr(test, allow(dead_code))]
    pub fn get_pending_cloud_oauth() -> Result<Option<String>, String> {
        Err(
            "Pending Cloud OAuth requests are only available in the supported macOS build"
                .to_string(),
        )
    }

    #[cfg_attr(test, allow(dead_code))]
    pub fn set_pending_cloud_oauth(pending: &str) -> Result<(), String> {
        super::validate_pending_cloud_oauth(pending)?;
        Err(
            "Pending Cloud OAuth requests are only available in the supported macOS build"
                .to_string(),
        )
    }

    #[cfg_attr(test, allow(dead_code))]
    pub fn delete_pending_cloud_oauth() -> Result<(), String> {
        Err(
            "Pending Cloud OAuth requests are only available in the supported macOS build"
                .to_string(),
        )
    }

    pub fn get_cloud_entitlement_snapshot() -> Result<Option<String>, String> {
        Err("Secure Cloud entitlements are only available in the supported macOS build".to_string())
    }

    pub fn set_cloud_entitlement_snapshot(token: &str) -> Result<(), String> {
        validate_cloud_entitlement_snapshot(token)?;
        Err("Secure Cloud entitlements are only available in the supported macOS build".to_string())
    }

    pub fn delete_cloud_entitlement_snapshot() -> Result<(), String> {
        Err("Secure Cloud entitlements are only available in the supported macOS build".to_string())
    }

    pub fn get_cloud_sync_device_key(_account_id: &str) -> Result<Option<[u8; 32]>, String> {
        Err("Secure Cloud sync is only available in the supported macOS build".to_string())
    }
    pub fn set_cloud_sync_device_key(_account_id: &str, _key: &[u8; 32]) -> Result<(), String> {
        Err("Secure Cloud sync is only available in the supported macOS build".to_string())
    }
    pub fn get_cloud_sync_account_key(_account_id: &str) -> Result<Option<[u8; 32]>, String> {
        Err("Secure Cloud sync is only available in the supported macOS build".to_string())
    }
    pub fn set_cloud_sync_account_key(_account_id: &str, _key: &[u8; 32]) -> Result<(), String> {
        Err("Secure Cloud sync is only available in the supported macOS build".to_string())
    }
    pub fn delete_cloud_sync_keys(_account_id: &str) -> Result<(), String> {
        Err("Secure Cloud sync is only available in the supported macOS build".to_string())
    }
}

#[cfg_attr(test, allow(unused_imports))]
pub use platform::{
    delete_cloud_bearer_token, delete_cloud_entitlement_snapshot, delete_cloud_oauth_token_set,
    delete_cloud_sync_keys, delete_history_master_key, delete_pending_cloud_oauth,
    get_cloud_bearer_token, get_cloud_entitlement_snapshot, get_cloud_oauth_token_set,
    get_cloud_sync_account_key, get_cloud_sync_device_key, get_history_master_key,
    get_pending_cloud_oauth, get_provider_api_key, migrate_legacy_cloud_oauth_token_set,
    migrate_legacy_openai_api_key, set_cloud_bearer_token, set_cloud_entitlement_snapshot,
    set_cloud_oauth_token_set, set_cloud_sync_account_key, set_cloud_sync_device_key,
    set_history_master_key, set_pending_cloud_oauth, set_provider_api_key,
};

pub fn get_or_create_history_master_key() -> Result<[u8; 32], String> {
    if let Some(key) = get_history_master_key()? {
        return Ok(key);
    }

    let key = crate::history_crypto::generate_master_key();
    set_history_master_key(&key)?;
    Ok(key)
}

#[cfg(test)]
mod tests {
    use super::{
        validate_cloud_bearer_token, validate_cloud_entitlement_snapshot, validate_provider_id,
    };

    #[test]
    fn provider_ids_are_restricted_before_keychain_access() {
        for valid in ["openai", "azure-openai", "provider_2"] {
            assert!(validate_provider_id(valid).is_ok());
        }

        for invalid in ["", "../openai", "provider/account", "provider name"] {
            assert!(validate_provider_id(invalid).is_err());
        }
    }

    #[test]
    fn cloud_bearer_tokens_are_bounded_and_single_line() {
        assert!(validate_cloud_bearer_token(&"a".repeat(32)).is_ok());
        assert!(validate_cloud_bearer_token("short").is_err());
        assert!(validate_cloud_bearer_token(&format!("{}\n", "a".repeat(32))).is_err());
        assert!(validate_cloud_bearer_token(&"a".repeat(4097)).is_err());
    }

    #[test]
    fn entitlement_snapshots_require_compact_jwt_shape() {
        let valid = format!("{}.{}.{}", "a".repeat(24), "b".repeat(24), "c".repeat(64));
        assert!(validate_cloud_entitlement_snapshot(&valid).is_ok());
        assert!(validate_cloud_entitlement_snapshot("header.payload").is_err());
        assert!(validate_cloud_entitlement_snapshot(&format!("{valid}\n")).is_err());
    }
}
