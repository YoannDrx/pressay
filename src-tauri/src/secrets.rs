const BYOK_SERVICE: &str = "app.pressay.desktop.byok";

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

#[cfg(target_os = "macos")]
mod platform {
    use super::{validate_provider_id, BYOK_SERVICE};
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

    fn entry(provider_id: &str) -> Result<Entry, String> {
        validate_provider_id(provider_id)?;
        initialize_store()?;
        Entry::new(BYOK_SERVICE, provider_id)
            .map_err(|_| "Unable to access the macOS Keychain".to_string())
    }

    pub fn get_provider_api_key(provider_id: &str) -> Result<Option<String>, String> {
        match entry(provider_id)?.get_password() {
            Ok(secret) => Ok(Some(secret)),
            Err(Error::NoEntry) => Ok(None),
            Err(_) => Err("Unable to read the API key from the macOS Keychain".to_string()),
        }
    }

    pub fn set_provider_api_key(provider_id: &str, api_key: &str) -> Result<(), String> {
        let entry = entry(provider_id)?;
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
}

#[cfg(not(target_os = "macos"))]
mod platform {
    use super::validate_provider_id;

    pub fn get_provider_api_key(provider_id: &str) -> Result<Option<String>, String> {
        validate_provider_id(provider_id)?;
        Err("Secure BYOK storage is only available in the supported macOS build".to_string())
    }

    pub fn set_provider_api_key(provider_id: &str, _api_key: &str) -> Result<(), String> {
        validate_provider_id(provider_id)?;
        Err("Secure BYOK storage is only available in the supported macOS build".to_string())
    }
}

pub use platform::{get_provider_api_key, set_provider_api_key};

#[cfg(test)]
mod tests {
    use super::validate_provider_id;

    #[test]
    fn provider_ids_are_restricted_before_keychain_access() {
        for valid in ["openai", "azure-openai", "provider_2"] {
            assert!(validate_provider_id(valid).is_ok());
        }

        for invalid in ["", "../openai", "provider/account", "provider name"] {
            assert!(validate_provider_id(invalid).is_err());
        }
    }
}
