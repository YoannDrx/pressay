const BYOK_SERVICE: &str = "app.pressay.desktop.byok";
const HISTORY_SERVICE: &str = "app.pressay.desktop.history";
const HISTORY_MASTER_KEY_ACCOUNT: &str = "master-key-v1";
const CLOUD_SERVICE: &str = "app.pressay.desktop.cloud";
const CLOUD_BEARER_ACCOUNT: &str = "bearer-token-v1";
const CLOUD_ENTITLEMENT_ACCOUNT: &str = "entitlement-snapshot-v1";

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

#[cfg(target_os = "macos")]
mod platform {
    use super::{
        validate_cloud_bearer_token, validate_cloud_entitlement_snapshot, validate_provider_id,
        BYOK_SERVICE, CLOUD_BEARER_ACCOUNT, CLOUD_ENTITLEMENT_ACCOUNT, CLOUD_SERVICE,
        HISTORY_MASTER_KEY_ACCOUNT, HISTORY_SERVICE,
    };
    use keyring_core::{Entry, Error};
    use std::sync::OnceLock;

    static STORE_INITIALIZED: OnceLock<Result<(), String>> = OnceLock::new();

    fn initialize_store() -> Result<(), String> {
        STORE_INITIALIZED
            .get_or_init(|| {
                if std::env::var_os("APP_SANDBOX_CONTAINER_ID").is_some() {
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

    fn entry(service: &str, account: &str) -> Result<Entry, String> {
        initialize_store()?;
        Entry::new(service, account).map_err(|_| "Unable to access the macOS Keychain".to_string())
    }

    pub fn get_provider_api_key(provider_id: &str) -> Result<Option<String>, String> {
        validate_provider_id(provider_id)?;
        match entry(BYOK_SERVICE, provider_id)?.get_password() {
            Ok(secret) => Ok(Some(secret)),
            Err(Error::NoEntry) => Ok(None),
            Err(_) => Err("Unable to read the API key from the macOS Keychain".to_string()),
        }
    }

    pub fn set_provider_api_key(provider_id: &str, api_key: &str) -> Result<(), String> {
        validate_provider_id(provider_id)?;
        let entry = entry(BYOK_SERVICE, provider_id)?;
        if api_key.is_empty() {
            return match entry.delete_credential() {
                Ok(()) | Err(Error::NoEntry) => Ok(()),
                Err(_) => Err("Unable to delete the API key from the macOS Keychain".to_string()),
            };
        }

        entry
            .set_password(api_key)
            .map_err(|_| "Unable to save the API key in the macOS Keychain".to_string())
    }

    pub fn get_history_master_key() -> Result<Option<[u8; 32]>, String> {
        match entry(HISTORY_SERVICE, HISTORY_MASTER_KEY_ACCOUNT)?.get_secret() {
            Ok(secret) => secret
                .try_into()
                .map(Some)
                .map_err(|_| "The history encryption key has an invalid format".to_string()),
            Err(Error::NoEntry) => Ok(None),
            Err(_) => Err("Unable to read the history key from the macOS Keychain".to_string()),
        }
    }

    pub fn set_history_master_key(key: &[u8; 32]) -> Result<(), String> {
        entry(HISTORY_SERVICE, HISTORY_MASTER_KEY_ACCOUNT)?
            .set_secret(key)
            .map_err(|_| "Unable to save the history key in the macOS Keychain".to_string())
    }

    pub fn delete_history_master_key() -> Result<(), String> {
        match entry(HISTORY_SERVICE, HISTORY_MASTER_KEY_ACCOUNT)?.delete_credential() {
            Ok(()) | Err(Error::NoEntry) => Ok(()),
            Err(_) => Err("Unable to delete the history key from the macOS Keychain".to_string()),
        }
    }

    pub fn get_cloud_bearer_token() -> Result<Option<String>, String> {
        match entry(CLOUD_SERVICE, CLOUD_BEARER_ACCOUNT)?.get_password() {
            Ok(token) => {
                validate_cloud_bearer_token(&token)?;
                Ok(Some(token))
            }
            Err(Error::NoEntry) => Ok(None),
            Err(_) => Err("Unable to read the Cloud session from macOS Keychain".to_string()),
        }
    }

    pub fn set_cloud_bearer_token(token: &str) -> Result<(), String> {
        validate_cloud_bearer_token(token)?;
        entry(CLOUD_SERVICE, CLOUD_BEARER_ACCOUNT)?
            .set_password(token)
            .map_err(|_| "Unable to save the Cloud session in macOS Keychain".to_string())
    }

    pub fn delete_cloud_bearer_token() -> Result<(), String> {
        match entry(CLOUD_SERVICE, CLOUD_BEARER_ACCOUNT)?.delete_credential() {
            Ok(()) | Err(Error::NoEntry) => Ok(()),
            Err(_) => Err("Unable to delete the Cloud session from macOS Keychain".to_string()),
        }
    }

    pub fn get_cloud_entitlement_snapshot() -> Result<Option<String>, String> {
        match entry(CLOUD_SERVICE, CLOUD_ENTITLEMENT_ACCOUNT)?.get_password() {
            Ok(token) => {
                validate_cloud_entitlement_snapshot(&token)?;
                Ok(Some(token))
            }
            Err(Error::NoEntry) => Ok(None),
            Err(_) => Err("Unable to read the Cloud entitlement from macOS Keychain".to_string()),
        }
    }

    pub fn set_cloud_entitlement_snapshot(token: &str) -> Result<(), String> {
        validate_cloud_entitlement_snapshot(token)?;
        entry(CLOUD_SERVICE, CLOUD_ENTITLEMENT_ACCOUNT)?
            .set_password(token)
            .map_err(|_| "Unable to save the Cloud entitlement in macOS Keychain".to_string())
    }

    pub fn delete_cloud_entitlement_snapshot() -> Result<(), String> {
        match entry(CLOUD_SERVICE, CLOUD_ENTITLEMENT_ACCOUNT)?.delete_credential() {
            Ok(()) | Err(Error::NoEntry) => Ok(()),
            Err(_) => Err("Unable to delete the Cloud entitlement from macOS Keychain".to_string()),
        }
    }
}

#[cfg(not(target_os = "macos"))]
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
}

pub use platform::{
    delete_cloud_bearer_token, delete_cloud_entitlement_snapshot, delete_history_master_key,
    get_cloud_bearer_token, get_cloud_entitlement_snapshot, get_history_master_key,
    get_provider_api_key, set_cloud_bearer_token, set_cloud_entitlement_snapshot,
    set_history_master_key, set_provider_api_key,
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
