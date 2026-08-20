use serde::{Deserialize, Serialize};
use specta::Type;
use tauri::AppHandle;

use crate::cloud::{self, EntitlementSource, EntitlementTier};
use crate::settings::get_settings;

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityAccess {
    Enabled,
    UpgradeRequired,
    ReleaseGate,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type)]
#[serde(rename_all = "snake_case")]
pub enum EntitlementState {
    LocalFree,
    Verified,
    Unavailable,
}

/// The single product matrix consumed by UI and backend gates. It deliberately
/// distinguishes commercial release gates from an ordinary Free entitlement:
/// unavailable payment infrastructure must never masquerade as a user upgrade.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct Capabilities {
    /// False in beta builds until checkout, restore and refund gates pass.
    /// The matrix remains visible while backend guards stay non-disruptive.
    pub entitlements_enforced: bool,
    pub tier: EntitlementTier,
    pub entitlement_source: EntitlementSource,
    pub entitlement_state: EntitlementState,
    pub entitlement_error: Option<String>,
    pub local_dictation: CapabilityAccess,
    pub local_history: CapabilityAccess,
    pub basic_dictionary: CapabilityAccess,
    pub deterministic_voice_commands: CapabilityAccess,
    pub custom_modes: CapabilityAccess,
    pub app_profiles: CapabilityAccess,
    pub voice_correction: CapabilityAccess,
    pub byok: CapabilityAccess,
    pub apple_intelligence: CapabilityAccess,
    pub encrypted_sync: CapabilityAccess,
    pub pressay_cloud: CapabilityAccess,
    pub direct_checkout: CapabilityAccess,
    pub app_store_purchase: CapabilityAccess,
}

impl Capabilities {
    fn for_tier(
        tier: EntitlementTier,
        source: EntitlementSource,
        state: EntitlementState,
        error: Option<String>,
    ) -> Self {
        let pro = if tier == EntitlementTier::Pro {
            CapabilityAccess::Enabled
        } else {
            CapabilityAccess::UpgradeRequired
        };
        Self {
            entitlements_enforced: cfg!(feature = "commercial-entitlements"),
            tier,
            entitlement_source: source,
            entitlement_state: state,
            entitlement_error: error,
            local_dictation: CapabilityAccess::Enabled,
            local_history: CapabilityAccess::Enabled,
            basic_dictionary: CapabilityAccess::Enabled,
            deterministic_voice_commands: CapabilityAccess::Enabled,
            custom_modes: pro,
            app_profiles: pro,
            voice_correction: pro,
            byok: pro,
            apple_intelligence: pro,
            encrypted_sync: pro,
            pressay_cloud: pro,
            // Kept closed until their respective end-to-end payment matrices pass.
            direct_checkout: CapabilityAccess::ReleaseGate,
            app_store_purchase: CapabilityAccess::ReleaseGate,
        }
    }

    pub fn local_free() -> Self {
        Self::for_tier(
            EntitlementTier::Free,
            EntitlementSource::None,
            EntitlementState::LocalFree,
            None,
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProductCapability {
    CustomModes,
    AppProfiles,
    VoiceCorrection,
    Byok,
    AppleIntelligence,
    EncryptedSync,
    PressayCloud,
}

impl ProductCapability {
    fn id(self) -> &'static str {
        match self {
            Self::CustomModes => "custom_modes",
            Self::AppProfiles => "app_profiles",
            Self::VoiceCorrection => "voice_correction",
            Self::Byok => "byok",
            Self::AppleIntelligence => "apple_intelligence",
            Self::EncryptedSync => "encrypted_sync",
            Self::PressayCloud => "pressay_cloud",
        }
    }
}

fn cached_capabilities(app: &AppHandle) -> Capabilities {
    let settings = get_settings(app);
    match cloud::cached_account_snapshot(&settings) {
        Ok(snapshot) => match snapshot.entitlement {
            Some(entitlement) => Capabilities::for_tier(
                entitlement.tier,
                entitlement.source,
                EntitlementState::Verified,
                None,
            ),
            None => Capabilities::local_free(),
        },
        Err(error) => Capabilities::for_tier(
            EntitlementTier::Free,
            EntitlementSource::None,
            EntitlementState::Unavailable,
            Some(error.code),
        ),
    }
}

/// Backend enforcement for every commercial surface. Beta builds deliberately
/// compile this as a no-op until both payment channels and account recovery are
/// validated; release builds opt in with `commercial-entitlements`.
pub fn require_capability(app: &AppHandle, capability: ProductCapability) -> Result<(), String> {
    if !cfg!(feature = "commercial-entitlements") {
        return Ok(());
    }
    let capabilities = cached_capabilities(app);
    let access = match capability {
        ProductCapability::CustomModes => capabilities.custom_modes,
        ProductCapability::AppProfiles => capabilities.app_profiles,
        ProductCapability::VoiceCorrection => capabilities.voice_correction,
        ProductCapability::Byok => capabilities.byok,
        ProductCapability::AppleIntelligence => capabilities.apple_intelligence,
        ProductCapability::EncryptedSync => capabilities.encrypted_sync,
        ProductCapability::PressayCloud => capabilities.pressay_cloud,
    };
    match access {
        CapabilityAccess::Enabled => Ok(()),
        CapabilityAccess::UpgradeRequired => {
            Err(format!("capability_upgrade_required:{}", capability.id()))
        }
        CapabilityAccess::ReleaseGate => {
            Err(format!("capability_release_gate:{}", capability.id()))
        }
    }
}

#[tauri::command]
#[specta::specta]
pub async fn get_capabilities(app: AppHandle) -> Capabilities {
    match cloud::account_snapshot(&app).await {
        Ok(snapshot) => match snapshot.entitlement {
            Some(entitlement) => Capabilities::for_tier(
                entitlement.tier,
                entitlement.source,
                EntitlementState::Verified,
                None,
            ),
            None => Capabilities::local_free(),
        },
        Err(error) => Capabilities::for_tier(
            EntitlementTier::Free,
            EntitlementSource::None,
            EntitlementState::Unavailable,
            Some(error.code),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn free_is_local_first_without_commercial_access() {
        let capabilities = Capabilities::local_free();
        assert_eq!(capabilities.local_dictation, CapabilityAccess::Enabled);
        assert_eq!(
            capabilities.entitlements_enforced,
            cfg!(feature = "commercial-entitlements")
        );
        assert_eq!(
            capabilities.deterministic_voice_commands,
            CapabilityAccess::Enabled
        );
        assert_eq!(capabilities.byok, CapabilityAccess::UpgradeRequired);
        assert_eq!(capabilities.direct_checkout, CapabilityAccess::ReleaseGate);
    }

    #[test]
    fn pro_unlocks_productivity_but_not_unvalidated_payments() {
        let capabilities = Capabilities::for_tier(
            EntitlementTier::Pro,
            EntitlementSource::Trial,
            EntitlementState::Verified,
            None,
        );
        assert_eq!(capabilities.voice_correction, CapabilityAccess::Enabled);
        assert_eq!(capabilities.encrypted_sync, CapabilityAccess::Enabled);
        assert_eq!(
            capabilities.app_store_purchase,
            CapabilityAccess::ReleaseGate
        );
    }
}
