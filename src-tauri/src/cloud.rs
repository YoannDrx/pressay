use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use reqwest::{Client, Response, StatusCode, Url};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use specta::Type;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter, Manager};
use url::form_urlencoded;

use crate::secrets::{
    delete_cloud_bearer_token, delete_cloud_entitlement_snapshot, delete_cloud_oauth_token_set,
    delete_cloud_sync_keys, get_cloud_bearer_token, get_cloud_entitlement_snapshot,
    get_cloud_oauth_token_set, get_cloud_sync_account_key, get_cloud_sync_device_key,
    migrate_legacy_cloud_oauth_token_set, set_cloud_bearer_token, set_cloud_entitlement_snapshot,
    set_cloud_oauth_token_set, set_cloud_sync_account_key, set_cloud_sync_device_key,
};
#[cfg(not(test))]
use crate::secrets::{
    delete_pending_cloud_oauth, get_pending_cloud_oauth, set_pending_cloud_oauth,
};
use crate::settings::{get_settings, write_settings, AppSettings};

const AUTH_STATE_TTL: Duration = Duration::from_secs(15 * 60);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(45);
const MAX_ERROR_CODE_LEN: usize = 80;
const STAGING_ENTITLEMENT_KEY_ID: &str = "pressay-entitlement-2026-01";
const STAGING_ENTITLEMENT_PUBLIC_KEY: &str = "gj3woVSEMEiNemiZKdA28oEvMrLL9iQPbiMPr_B-plQ";
const PRODUCTION_ENTITLEMENT_KEY_ID: &str = "pressay-entitlement-production-2026-01";
const PRODUCTION_ENTITLEMENT_PUBLIC_KEY: &str = "Xm5Rqwpjhv85nc7Y_Lrf3S7M40iCozJCrFh1UCXeoF0";
const DEFAULT_ENTITLEMENT_ISSUER: &str = "https://api.press-say.app";
const OAUTH_ISSUER: &str = "https://press-say.app";
const OAUTH_CLIENT_ID: &str = "w9ckUgrcFp7H7wNV";
const OAUTH_RESOURCE: &str = "https://api.press-say.app";
const OAUTH_REDIRECT_URI: &str = "pressay://oauth/callback";
const OAUTH_SCOPE: &str = "openid profile email offline_access";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct EntitlementVerifierConfig {
    key_id: &'static str,
    public_key: &'static str,
    issuer: &'static str,
}

fn default_entitlement_verifier_config(version: &str) -> EntitlementVerifierConfig {
    if version.contains('-') {
        EntitlementVerifierConfig {
            key_id: STAGING_ENTITLEMENT_KEY_ID,
            public_key: STAGING_ENTITLEMENT_PUBLIC_KEY,
            issuer: DEFAULT_ENTITLEMENT_ISSUER,
        }
    } else {
        EntitlementVerifierConfig {
            key_id: PRODUCTION_ENTITLEMENT_KEY_ID,
            public_key: PRODUCTION_ENTITLEMENT_PUBLIC_KEY,
            issuer: DEFAULT_ENTITLEMENT_ISSUER,
        }
    }
}

fn entitlement_verifier_config() -> Result<EntitlementVerifierConfig, CloudFailure> {
    let defaults = default_entitlement_verifier_config(env!("CARGO_PKG_VERSION"));
    match (
        option_env!("PRESSAY_ENTITLEMENT_KEY_ID"),
        option_env!("PRESSAY_ENTITLEMENT_PUBLIC_KEY"),
    ) {
        (Some(key_id), Some(public_key)) if !key_id.is_empty() && !public_key.is_empty() => {
            Ok(EntitlementVerifierConfig {
                key_id,
                public_key,
                issuer: option_env!("PRESSAY_ENTITLEMENT_ISSUER")
                    .unwrap_or(DEFAULT_ENTITLEMENT_ISSUER),
            })
        }
        (None, None) => Ok(EntitlementVerifierConfig {
            issuer: option_env!("PRESSAY_ENTITLEMENT_ISSUER").unwrap_or(DEFAULT_ENTITLEMENT_ISSUER),
            ..defaults
        }),
        _ => Err(CloudFailure::new("cloud_entitlement_config_invalid")),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CloudFailure {
    pub code: String,
}

impl CloudFailure {
    fn new(code: &str) -> Self {
        Self {
            code: safe_error_code(code),
        }
    }

    pub(crate) fn from_code(code: &str) -> Self {
        Self::new(code)
    }
}

impl std::fmt::Display for CloudFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.code)
    }
}

impl std::error::Error for CloudFailure {}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type)]
#[serde(rename_all = "snake_case")]
pub enum CloudAuthProvider {
    Google,
    Apple,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct CloudAuthConfig {
    pub magic_link: bool,
    pub providers: Vec<CloudAuthProvider>,
    pub callback_url: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type)]
#[serde(rename_all = "snake_case")]
pub enum EntitlementTier {
    Free,
    Pro,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type)]
#[serde(rename_all = "snake_case")]
pub enum EntitlementSource {
    None,
    Trial,
    Stripe,
    AppStore,
    Support,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct EntitlementSnapshot {
    pub tier: EntitlementTier,
    pub source: EntitlementSource,
    pub valid_from: String,
    pub valid_until: Option<String>,
    pub offline_grace_until: Option<String>,
    pub revision: u64,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptionUsage {
    pub used_seconds: u64,
    pub reserved_seconds: u64,
    pub limit_seconds: u64,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct TransformationUsage {
    pub used: u64,
    pub reserved: u64,
    pub limit: u64,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct UsageSnapshot {
    pub period_start: String,
    pub transcription: TranscriptionUsage,
    pub transformations: TransformationUsage,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct CloudAccountSnapshot {
    pub connected: bool,
    pub account_id: Option<String>,
    pub email: Option<String>,
    pub device_id: Option<String>,
    pub entitlement: Option<EntitlementSnapshot>,
    pub usage: Option<UsageSnapshot>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RestoreAppStoreRequest<'a> {
    signed_transaction: &'a str,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RestoreAppStoreResponse {
    restored: bool,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type)]
#[serde(rename_all = "snake_case")]
pub enum CloudSyncStatus {
    NotConfigured,
    PendingApproval,
    Ready,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct CloudSyncDevice {
    pub id: String,
    pub display_name: String,
    pub status: CloudSyncStatus,
    pub current: bool,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct CloudSyncSnapshot {
    pub status: CloudSyncStatus,
    pub devices: Vec<CloudSyncDevice>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct CloudSyncRecoveryCode {
    pub code: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SyncObjectType {
    Mode,
    Profile,
    Dictionary,
    Preference,
}

impl SyncObjectType {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Mode => "mode",
            Self::Profile => "profile",
            Self::Dictionary => "dictionary",
            Self::Preference => "preference",
        }
    }
}

#[derive(Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SyncChangeInput {
    pub object_type: SyncObjectType,
    pub object_id: String,
    pub revision: u64,
    pub envelope: String,
    pub envelope_version: u8,
    pub tombstone: bool,
}

#[derive(Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SyncChangeOutput {
    pub object_type: SyncObjectType,
    pub object_id: String,
    pub revision: u64,
    pub envelope: String,
    pub envelope_version: u8,
    pub tombstone: bool,
    pub sequence_id: u64,
    pub source_device_id: String,
    pub conflict: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AppendSyncChangesResponse {
    accepted: u64,
    conflicts: u64,
    cursor: u64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncChangesResponse {
    pub changes: Vec<SyncChangeOutput>,
    pub next_cursor: u64,
    pub has_more: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AppendSyncChangesRequest<'a> {
    device_id: &'a str,
    changes: &'a [SyncChangeInput],
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct CloudAuthEvent {
    pub status: CloudAuthEventStatus,
    pub error_code: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type)]
#[serde(rename_all = "snake_case")]
pub enum CloudAuthEventStatus {
    Exchanging,
    Bootstrapping,
    Connected,
    Failed,
}

#[derive(Debug)]
struct PendingAuth {
    state: String,
    verifier: Option<String>,
    created_at: Instant,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PendingOAuthRecord {
    state: String,
    verifier: String,
    created_at: i64,
}

#[cfg(not(test))]
fn save_pending_oauth(encoded: &str) -> Result<(), String> {
    set_pending_cloud_oauth(encoded)
}

#[cfg(test)]
fn save_pending_oauth(_encoded: &str) -> Result<(), String> {
    Ok(())
}

#[cfg(not(test))]
fn load_pending_oauth() -> Result<Option<String>, String> {
    get_pending_cloud_oauth()
}

#[cfg(test)]
fn load_pending_oauth() -> Result<Option<String>, String> {
    Ok(None)
}

#[cfg(not(test))]
fn clear_pending_oauth() -> Result<(), String> {
    delete_pending_cloud_oauth()
}

#[cfg(test)]
fn clear_pending_oauth() -> Result<(), String> {
    Ok(())
}

#[derive(Default)]
pub struct CloudAuthRuntime {
    pending: Mutex<Option<PendingAuth>>,
}

impl CloudAuthRuntime {
    pub fn begin(&self) -> Result<String, CloudFailure> {
        self.begin_pending(None)
    }

    pub fn begin_oauth(&self) -> Result<(String, String), CloudFailure> {
        let verifier = URL_SAFE_NO_PAD.encode(crate::history_crypto::generate_master_key());
        let state = self.begin_pending(Some(verifier.clone()))?;
        let record = PendingOAuthRecord {
            state: state.clone(),
            verifier: verifier.clone(),
            created_at: chrono::Utc::now().timestamp(),
        };
        let encoded = serde_json::to_string(&record)
            .map_err(|_| CloudFailure::new("cloud_auth_state_unavailable"))?;
        if save_pending_oauth(&encoded).is_err() {
            self.clear();
            return Err(CloudFailure::new("cloud_keychain_unavailable"));
        }
        Ok((state, verifier))
    }

    fn begin_pending(&self, verifier: Option<String>) -> Result<String, CloudFailure> {
        let state = URL_SAFE_NO_PAD.encode(crate::history_crypto::generate_master_key());
        let mut pending = self
            .pending
            .lock()
            .map_err(|_| CloudFailure::new("cloud_auth_state_unavailable"))?;
        *pending = Some(PendingAuth {
            state: state.clone(),
            verifier,
            created_at: Instant::now(),
        });
        Ok(state)
    }

    fn consume(&self, state: &str) -> Result<Option<String>, CloudFailure> {
        let mut pending = self
            .pending
            .lock()
            .map_err(|_| CloudFailure::new("cloud_auth_state_unavailable"))?;
        if let Some(candidate) = pending.take() {
            let valid =
                candidate.created_at.elapsed() <= AUTH_STATE_TTL && candidate.state == state;
            if candidate.verifier.is_some() {
                let _ = clear_pending_oauth();
            }
            return if valid {
                Ok(candidate.verifier)
            } else {
                Err(CloudFailure::new("cloud_auth_state_mismatch"))
            };
        }

        let encoded = load_pending_oauth()
            .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?
            .ok_or_else(|| CloudFailure::new("cloud_auth_state_mismatch"))?;
        let _ = clear_pending_oauth();
        let persisted: PendingOAuthRecord = serde_json::from_str(&encoded)
            .map_err(|_| CloudFailure::new("cloud_auth_state_mismatch"))?;
        let age = chrono::Utc::now().timestamp() - persisted.created_at;
        if persisted.state != state
            || !(0..=AUTH_STATE_TTL.as_secs() as i64).contains(&age)
            || !(43..=128).contains(&persisted.verifier.len())
        {
            return Err(CloudFailure::new("cloud_auth_state_mismatch"));
        }
        Ok(Some(persisted.verifier))
    }

    pub fn clear(&self) {
        if let Ok(mut pending) = self.pending.lock() {
            pending.take();
        }
        let _ = clear_pending_oauth();
    }
}

#[derive(Deserialize)]
struct OAuthMetadata {
    #[serde(rename = "authorization_endpoint")]
    authorization_endpoint: Url,
    #[serde(rename = "token_endpoint")]
    token_endpoint: Url,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct OAuthTokenSet {
    access_token: String,
    refresh_token: Option<String>,
    expires_at: i64,
}

#[derive(Deserialize)]
struct OAuthTokenResponse {
    access_token: String,
    refresh_token: Option<String>,
    expires_in: i64,
}

#[derive(Deserialize)]
struct LegacyOAuthTokenSet {
    access_token: String,
    refresh_token: Option<String>,
    expires_at: String,
}

#[derive(Debug, PartialEq, Eq)]
enum AuthCallback {
    OAuth { code: String, state: String },
    Legacy { token: String, state: String },
}

#[derive(Deserialize)]
struct ApiErrorBody {
    error: ApiErrorValue,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum ApiErrorValue {
    Structured { code: String },
    Code(String),
}

impl ApiErrorValue {
    fn code(&self) -> &str {
        match self {
            Self::Structured { code } | Self::Code(code) => code,
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct MagicLinkRequest<'a> {
    email: &'a str,
    callback_url: &'a str,
    error_callback_url: &'a str,
}

#[derive(Serialize)]
struct OneTimeTokenRequest<'a> {
    token: &'a str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct BootstrapRequest<'a> {
    device_identifier: &'a str,
    display_name: &'a str,
    app_variant: &'a str,
    app_version: &'a str,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct BootstrapResponse {
    account_id: String,
    device: BootstrapDevice,
    entitlement: EntitlementSnapshot,
}

#[derive(Deserialize)]
struct BootstrapDevice {
    id: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct EnrollSyncDeviceRequest<'a> {
    device_id: &'a str,
    public_key: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    encrypted_account_key: Option<&'a str>,
}

#[derive(Deserialize)]
struct EnrollSyncDeviceResponse {
    status: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SyncDeviceResponse {
    id: String,
    display_name: String,
    public_key: String,
    status: String,
}

#[derive(Deserialize)]
struct SyncDeviceListResponse {
    devices: Vec<SyncDeviceResponse>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SyncDeviceEnvelopeResponse {
    encrypted_account_key: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ApproveSyncDeviceRequest<'a> {
    approver_device_id: &'a str,
    encrypted_account_key: &'a str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ConfigureSyncRecoveryRequest<'a> {
    device_id: &'a str,
    code_hash: &'a str,
    encrypted_account_key: &'a str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct BeginSyncRecoveryRequest<'a> {
    device_id: &'a str,
    public_key: &'a str,
    code_hash: &'a str,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SyncRecoveryEnvelopeResponse {
    encrypted_account_key: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CompleteSyncRecoveryRequest<'a> {
    device_id: &'a str,
    code_hash: &'a str,
    encrypted_account_key: &'a str,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct MeResponse {
    account_id: String,
    email: String,
    entitlement: EntitlementSnapshot,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct EntitlementResponse {
    entitlement: EntitlementSnapshot,
    usage: UsageSnapshot,
    signed_snapshot: SignedEntitlementSnapshot,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SignedEntitlementSnapshot {
    token: String,
    key_id: String,
    expires_at: String,
}

#[derive(Deserialize)]
struct EntitlementJwtHeader {
    alg: String,
    kid: String,
    typ: String,
}

#[derive(Deserialize)]
struct EntitlementJwtUsage {
    period_start: String,
    transcription_seconds_used: u64,
    transcription_seconds_limit: u64,
    transformations_used: u64,
    transformations_limit: u64,
}

#[derive(Deserialize)]
struct EntitlementJwtClaims {
    tier: EntitlementTier,
    source: EntitlementSource,
    revision: u64,
    device_id: String,
    online_valid_until: Option<i64>,
    offline_grace_until: Option<i64>,
    usage: EntitlementJwtUsage,
    iss: String,
    aud: Vec<String>,
    sub: String,
    iat: i64,
    exp: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CloudTransformationRequest<'a> {
    pub device_id: &'a str,
    pub transcript: &'a str,
    pub instruction: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub selected_text: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub application_name: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub language: Option<&'a str>,
    pub content_transfer_acknowledged: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CloudTransformationResponse {
    pub text: String,
    pub model_alias: String,
    pub operation_id: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Type)]
#[serde(rename_all = "camelCase")]
pub struct CloudTranscriptionResponse {
    pub text: String,
    pub model_alias: String,
    pub operation_id: String,
    pub duration_seconds: f64,
}

fn client() -> &'static Client {
    static CLIENT: OnceLock<Client> = OnceLock::new();
    CLIENT.get_or_init(|| {
        Client::builder()
            .timeout(REQUEST_TIMEOUT)
            .user_agent(concat!("Pressay/", env!("CARGO_PKG_VERSION")))
            .build()
            .expect("Pressay Cloud HTTP client configuration is valid")
    })
}

fn safe_error_code(code: &str) -> String {
    if !code.is_empty()
        && code.len() <= MAX_ERROR_CODE_LEN
        && code
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || character == '_')
    {
        code.to_string()
    } else {
        "cloud_request_failed".to_string()
    }
}

fn validate_base_url(raw: &str) -> Result<Url, CloudFailure> {
    let url = Url::parse(raw).map_err(|_| CloudFailure::new("cloud_api_url_invalid"))?;
    let host = url
        .host_str()
        .ok_or_else(|| CloudFailure::new("cloud_api_url_invalid"))?;
    let configured_host = option_env!("PRESSAY_CLOUD_API_URL")
        .and_then(|value| Url::parse(value).ok())
        .and_then(|value| value.host_str().map(str::to_owned));
    let allowed = url.scheme() == "https"
        && (host == "api.press-say.app"
            || host == "api-staging.press-say.app"
            || host == "pressay-cloud-staging.vercel.app"
            || configured_host.as_deref() == Some(host));
    #[cfg(test)]
    let allowed = allowed || (url.scheme() == "http" && matches!(host, "127.0.0.1" | "localhost"));
    if !allowed || url.query().is_some() || url.fragment().is_some() {
        return Err(CloudFailure::new("cloud_api_url_not_allowed"));
    }
    Ok(url)
}

fn endpoint(settings: &AppSettings, path: &str) -> Result<Url, CloudFailure> {
    validate_base_url(&settings.pressay_cloud_api_url)?
        .join(path)
        .map_err(|_| CloudFailure::new("cloud_api_url_invalid"))
}

fn apple_browser_login_url(settings: &AppSettings, state: &str) -> Result<Url, CloudFailure> {
    let mut url = endpoint(settings, "/v1/desktop-auth/social/apple")?;
    url.query_pairs_mut().append_pair("state", state);
    Ok(url)
}

async fn finish(response: Response) -> Result<Response, CloudFailure> {
    if response.status().is_success() {
        return Ok(response);
    }
    let status = response.status();
    let code = response
        .json::<ApiErrorBody>()
        .await
        .ok()
        .map(|body| safe_error_code(body.error.code()))
        .unwrap_or_else(|| status_error_code(status).to_string());
    Err(CloudFailure::new(&code))
}

fn status_error_code(status: StatusCode) -> &'static str {
    match status.as_u16() {
        401 => "cloud_unauthorized",
        403 => "cloud_forbidden",
        404 => "cloud_not_found",
        409 => "cloud_conflict",
        422 => "cloud_invalid_request",
        429 => "cloud_rate_limited",
        503 => "cloud_unavailable",
        _ => "cloud_request_failed",
    }
}

async fn json<T: DeserializeOwned>(response: Response) -> Result<T, CloudFailure> {
    finish(response)
        .await?
        .json::<T>()
        .await
        .map_err(|_| CloudFailure::new("cloud_response_invalid"))
}

fn legacy_bearer() -> Result<String, CloudFailure> {
    get_cloud_bearer_token()
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?
        .ok_or_else(|| CloudFailure::new("cloud_not_connected"))
}

fn validate_oauth_endpoint(url: &Url) -> Result<(), CloudFailure> {
    if url.scheme() == "https" && url.host_str() == Some("press-say.app") {
        Ok(())
    } else {
        Err(CloudFailure::new("cloud_oauth_endpoint_invalid"))
    }
}

async fn oauth_metadata() -> Result<OAuthMetadata, CloudFailure> {
    let metadata_url = Url::parse(&format!(
        "{OAUTH_ISSUER}/.well-known/oauth-authorization-server"
    ))
    .map_err(|_| CloudFailure::new("cloud_oauth_configuration_invalid"))?;
    let response = client()
        .get(metadata_url)
        .send()
        .await
        .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?;
    let metadata: OAuthMetadata = json(response).await?;
    validate_oauth_endpoint(&metadata.authorization_endpoint)?;
    validate_oauth_endpoint(&metadata.token_endpoint)?;
    Ok(metadata)
}

fn persist_oauth_token_set(token_set: &OAuthTokenSet) -> Result<(), CloudFailure> {
    let encoded = serde_json::to_string(token_set)
        .map_err(|_| CloudFailure::new("cloud_auth_token_invalid"))?;
    set_cloud_oauth_token_set(&encoded)
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?;
    set_cloud_bearer_token(&token_set.access_token)
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))
}

fn stored_oauth_token_set() -> Result<Option<OAuthTokenSet>, CloudFailure> {
    migrate_legacy_cloud_oauth_token_set()
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?;
    let Some(encoded) =
        get_cloud_oauth_token_set().map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?
    else {
        return Ok(None);
    };
    if let Ok(token_set) = serde_json::from_str(&encoded) {
        return Ok(Some(token_set));
    }
    let legacy: LegacyOAuthTokenSet = serde_json::from_str(&encoded)
        .map_err(|_| CloudFailure::new("cloud_auth_token_invalid"))?;
    let expires_at = chrono::DateTime::parse_from_rfc3339(&legacy.expires_at)
        .map_err(|_| CloudFailure::new("cloud_auth_token_invalid"))?
        .timestamp();
    let migrated = OAuthTokenSet {
        access_token: legacy.access_token,
        refresh_token: legacy.refresh_token,
        expires_at,
    };
    persist_oauth_token_set(&migrated)?;
    Ok(Some(migrated))
}

async fn request_oauth_tokens(
    parameters: &[(&str, &str)],
) -> Result<OAuthTokenResponse, CloudFailure> {
    let metadata = oauth_metadata().await?;
    let response = client()
        .post(metadata.token_endpoint)
        .form(parameters)
        .send()
        .await
        .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?;
    let tokens: OAuthTokenResponse = json(response).await?;
    if tokens.access_token.len() < 32
        || tokens.expires_in <= 0
        || tokens
            .refresh_token
            .as_ref()
            .is_some_and(|token| token.len() < 32)
    {
        return Err(CloudFailure::new("cloud_auth_token_invalid"));
    }
    Ok(tokens)
}

async fn exchange_oauth_code(code: &str, verifier: &str) -> Result<(), CloudFailure> {
    if code.is_empty() || code.len() > 4096 || verifier.len() < 43 || verifier.len() > 128 {
        return Err(CloudFailure::new("cloud_auth_token_invalid"));
    }
    let response = request_oauth_tokens(&[
        ("grant_type", "authorization_code"),
        ("client_id", OAUTH_CLIENT_ID),
        ("code", code),
        ("code_verifier", verifier),
        ("redirect_uri", OAUTH_REDIRECT_URI),
        ("resource", OAUTH_RESOURCE),
    ])
    .await?;
    persist_oauth_token_set(&OAuthTokenSet {
        access_token: response.access_token,
        refresh_token: response.refresh_token,
        expires_at: chrono::Utc::now().timestamp() + response.expires_in,
    })
}

async fn access_token() -> Result<String, CloudFailure> {
    let Some(current) = stored_oauth_token_set()? else {
        return legacy_bearer();
    };
    if current.expires_at > chrono::Utc::now().timestamp() + 60 {
        return Ok(current.access_token);
    }
    let refresh_token = current
        .refresh_token
        .as_deref()
        .ok_or_else(|| CloudFailure::new("cloud_session_expired"))?;
    let response = request_oauth_tokens(&[
        ("grant_type", "refresh_token"),
        ("client_id", OAUTH_CLIENT_ID),
        ("refresh_token", refresh_token),
        ("resource", OAUTH_RESOURCE),
    ])
    .await?;
    let refreshed = OAuthTokenSet {
        access_token: response.access_token,
        refresh_token: response.refresh_token.or(current.refresh_token),
        expires_at: chrono::Utc::now().timestamp() + response.expires_in,
    };
    let access_token = refreshed.access_token.clone();
    persist_oauth_token_set(&refreshed)?;
    Ok(access_token)
}

fn iso_timestamp(seconds: i64) -> Result<String, CloudFailure> {
    chrono::DateTime::from_timestamp(seconds, 0)
        .map(|value| value.to_rfc3339_opts(chrono::SecondsFormat::Secs, true))
        .ok_or_else(|| CloudFailure::new("cloud_entitlement_invalid"))
}

fn verify_entitlement_token(
    token: &str,
    settings: &AppSettings,
    now_seconds: i64,
) -> Result<(EntitlementSnapshot, UsageSnapshot), CloudFailure> {
    let verifier = entitlement_verifier_config()?;
    let public_key_bytes: [u8; 32] = URL_SAFE_NO_PAD
        .decode(verifier.public_key)
        .map_err(|_| CloudFailure::new("cloud_entitlement_invalid"))?
        .try_into()
        .map_err(|_| CloudFailure::new("cloud_entitlement_invalid"))?;
    verify_entitlement_token_with_config(token, settings, now_seconds, &public_key_bytes, verifier)
}

#[cfg(test)]
fn verify_entitlement_token_with_key(
    token: &str,
    settings: &AppSettings,
    now_seconds: i64,
    public_key_bytes: &[u8; 32],
) -> Result<(EntitlementSnapshot, UsageSnapshot), CloudFailure> {
    verify_entitlement_token_with_config(
        token,
        settings,
        now_seconds,
        public_key_bytes,
        entitlement_verifier_config()?,
    )
}

fn verify_entitlement_token_with_config(
    token: &str,
    settings: &AppSettings,
    now_seconds: i64,
    public_key_bytes: &[u8; 32],
    verifier: EntitlementVerifierConfig,
) -> Result<(EntitlementSnapshot, UsageSnapshot), CloudFailure> {
    let mut parts = token.split('.');
    let header_part = parts
        .next()
        .ok_or_else(|| CloudFailure::new("cloud_entitlement_invalid"))?;
    let claims_part = parts
        .next()
        .ok_or_else(|| CloudFailure::new("cloud_entitlement_invalid"))?;
    let signature_part = parts
        .next()
        .ok_or_else(|| CloudFailure::new("cloud_entitlement_invalid"))?;
    if parts.next().is_some() {
        return Err(CloudFailure::new("cloud_entitlement_invalid"));
    }

    let header: EntitlementJwtHeader = serde_json::from_slice(
        &URL_SAFE_NO_PAD
            .decode(header_part)
            .map_err(|_| CloudFailure::new("cloud_entitlement_invalid"))?,
    )
    .map_err(|_| CloudFailure::new("cloud_entitlement_invalid"))?;
    if header.alg != "EdDSA" || header.kid != verifier.key_id || header.typ != "JWT" {
        return Err(CloudFailure::new("cloud_entitlement_invalid"));
    }

    let claims: EntitlementJwtClaims = serde_json::from_slice(
        &URL_SAFE_NO_PAD
            .decode(claims_part)
            .map_err(|_| CloudFailure::new("cloud_entitlement_invalid"))?,
    )
    .map_err(|_| CloudFailure::new("cloud_entitlement_invalid"))?;
    let signature = Signature::from_slice(
        &URL_SAFE_NO_PAD
            .decode(signature_part)
            .map_err(|_| CloudFailure::new("cloud_entitlement_invalid"))?,
    )
    .map_err(|_| CloudFailure::new("cloud_entitlement_invalid"))?;
    VerifyingKey::from_bytes(public_key_bytes)
        .map_err(|_| CloudFailure::new("cloud_entitlement_invalid"))?
        .verify(
            format!("{header_part}.{claims_part}").as_bytes(),
            &signature,
        )
        .map_err(|_| CloudFailure::new("cloud_entitlement_invalid"))?;

    let expected_audience = if cfg!(feature = "mas") {
        "fr.yodev.pressay"
    } else {
        "app.pressay.desktop"
    };
    if claims.iss != verifier.issuer
        || !claims
            .aud
            .iter()
            .any(|audience| audience == expected_audience)
        || settings.pressay_cloud_account_id.as_deref() != Some(claims.sub.as_str())
        || settings.pressay_cloud_device_id.as_deref() != Some(claims.device_id.as_str())
        || claims.iat > now_seconds.saturating_add(300)
        || claims.exp <= now_seconds
        || claims.revision == 0
    {
        return Err(CloudFailure::new("cloud_entitlement_invalid"));
    }

    Ok((
        EntitlementSnapshot {
            tier: claims.tier,
            source: claims.source,
            valid_from: iso_timestamp(claims.iat)?,
            valid_until: claims.online_valid_until.map(iso_timestamp).transpose()?,
            offline_grace_until: claims.offline_grace_until.map(iso_timestamp).transpose()?,
            revision: claims.revision,
        },
        UsageSnapshot {
            period_start: claims.usage.period_start,
            transcription: TranscriptionUsage {
                used_seconds: claims.usage.transcription_seconds_used,
                reserved_seconds: 0,
                limit_seconds: claims.usage.transcription_seconds_limit,
            },
            transformations: TransformationUsage {
                used: claims.usage.transformations_used,
                reserved: 0,
                limit: claims.usage.transformations_limit,
            },
        },
    ))
}

pub(crate) fn cached_account_snapshot(
    settings: &AppSettings,
) -> Result<CloudAccountSnapshot, CloudFailure> {
    let token = get_cloud_entitlement_snapshot()
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?
        .ok_or_else(|| CloudFailure::new("cloud_network_unavailable"))?;
    let (entitlement, usage) =
        verify_entitlement_token(&token, settings, chrono::Utc::now().timestamp())?;
    let mut snapshot = CloudAccountSnapshot {
        connected: true,
        account_id: settings.pressay_cloud_account_id.clone(),
        email: None,
        device_id: settings.pressay_cloud_device_id.clone(),
        entitlement: Some(entitlement),
        usage: Some(usage),
    };
    if let Some(live) = last_account_snapshot().filter(|live| {
        live.account_id == snapshot.account_id && live.device_id == snapshot.device_id
    }) {
        snapshot.email = live.email;
    }
    Ok(snapshot)
}

fn account_snapshot_cache() -> &'static Mutex<Option<CloudAccountSnapshot>> {
    static CACHE: OnceLock<Mutex<Option<CloudAccountSnapshot>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(None))
}

fn remember_account_snapshot(snapshot: &CloudAccountSnapshot) {
    if let Ok(mut cached) = account_snapshot_cache().lock() {
        *cached = Some(snapshot.clone());
    }
}

fn last_account_snapshot() -> Option<CloudAccountSnapshot> {
    account_snapshot_cache()
        .lock()
        .ok()
        .and_then(|cached| cached.clone())
}

fn clear_account_snapshot_cache() {
    if let Ok(mut cached) = account_snapshot_cache().lock() {
        *cached = None;
    }
}

fn callback_urls(config: &CloudAuthConfig, state: &str) -> Result<(String, String), CloudFailure> {
    let mut callback = Url::parse(&config.callback_url)
        .map_err(|_| CloudFailure::new("cloud_auth_callback_invalid"))?;
    callback.query_pairs_mut().append_pair("state", state);
    let mut error_callback = Url::parse("pressay://oauth/error")
        .map_err(|_| CloudFailure::new("cloud_auth_callback_invalid"))?;
    error_callback.query_pairs_mut().append_pair("state", state);
    Ok((callback.to_string(), error_callback.to_string()))
}

pub async fn get_auth_config(settings: &AppSettings) -> Result<CloudAuthConfig, CloudFailure> {
    let remote = client()
        .get(endpoint(settings, "/v1/desktop-auth/config")?)
        .send()
        .await;
    let mut config = match remote {
        Ok(response) => json(response).await.unwrap_or(CloudAuthConfig {
            magic_link: false,
            providers: Vec::new(),
            callback_url: OAUTH_REDIRECT_URI.to_string(),
        }),
        Err(_) => CloudAuthConfig {
            magic_link: false,
            providers: Vec::new(),
            callback_url: OAUTH_REDIRECT_URI.to_string(),
        },
    };
    if !config.providers.contains(&CloudAuthProvider::Google) {
        config.providers.push(CloudAuthProvider::Google);
    }
    config.callback_url = OAUTH_REDIRECT_URI.to_string();
    Ok(config)
}

pub async fn request_magic_link(
    settings: &AppSettings,
    email: &str,
    state: &str,
) -> Result<(), CloudFailure> {
    if email.len() > 254 || !email.contains('@') {
        return Err(CloudFailure::new("cloud_email_invalid"));
    }
    let config = get_auth_config(settings).await?;
    if !config.magic_link {
        return Err(CloudFailure::new("cloud_magic_link_unavailable"));
    }
    let (callback_url, error_callback_url) = callback_urls(&config, state)?;
    let response = client()
        .post(endpoint(settings, "/v1/auth/sign-in/magic-link")?)
        .json(&MagicLinkRequest {
            email,
            callback_url: &callback_url,
            error_callback_url: &error_callback_url,
        })
        .send()
        .await
        .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?;
    finish(response).await?;
    Ok(())
}

pub async fn social_login_url(
    settings: &AppSettings,
    provider: CloudAuthProvider,
    state: &str,
    verifier: &str,
) -> Result<String, CloudFailure> {
    if state.len() < 32 {
        return Err(CloudFailure::new("cloud_auth_state_invalid"));
    }

    if provider == CloudAuthProvider::Apple {
        // Better Auth must create its signed provider-state cookie in the
        // user's browser. The API route then redirects the same browser to
        // Apple and receives Apple's form_post callback with that cookie.
        return Ok(apple_browser_login_url(settings, state)?.to_string());
    }

    if verifier.len() < 43 || verifier.len() > 128 {
        return Err(CloudFailure::new("cloud_auth_state_invalid"));
    }

    let metadata = oauth_metadata().await?;
    let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
    let mut authorization_url = metadata.authorization_endpoint;
    authorization_url
        .query_pairs_mut()
        .append_pair("response_type", "code")
        .append_pair("client_id", OAUTH_CLIENT_ID)
        .append_pair("redirect_uri", OAUTH_REDIRECT_URI)
        .append_pair("scope", OAUTH_SCOPE)
        .append_pair("state", state)
        .append_pair("code_challenge", &challenge)
        .append_pair("code_challenge_method", "S256")
        .append_pair("resource", OAUTH_RESOURCE);
    Ok(authorization_url.to_string())
}

pub(crate) fn uses_native_oauth_pkce(provider: CloudAuthProvider) -> bool {
    provider != CloudAuthProvider::Apple
}

async fn exchange_one_time_token(settings: &AppSettings, token: &str) -> Result<(), CloudFailure> {
    if token.len() < 16 || token.len() > 512 {
        return Err(CloudFailure::new("cloud_auth_token_invalid"));
    }
    let response = client()
        .post(endpoint(settings, "/v1/auth/one-time-token/verify")?)
        .json(&OneTimeTokenRequest { token })
        .send()
        .await
        .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?;
    let response = finish(response).await?;
    let bearer = response
        .headers()
        .get("set-auth-token")
        .and_then(|value| value.to_str().ok())
        .ok_or_else(|| CloudFailure::new("cloud_auth_bearer_missing"))?;
    set_cloud_bearer_token(bearer).map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))
}

async fn bootstrap_device(app: &AppHandle) -> Result<(), CloudFailure> {
    let mut settings = get_settings(app);
    if settings.pressay_cloud_device_identifier.is_empty() {
        settings.pressay_cloud_device_identifier =
            format!("pressay-device:{}", uuid::Uuid::new_v4());
        write_settings(app, settings.clone());
    }
    let token = access_token().await?;
    let response = client()
        .post(endpoint(&settings, "/v1/accounts/bootstrap")?)
        .bearer_auth(token)
        .json(&BootstrapRequest {
            device_identifier: &settings.pressay_cloud_device_identifier,
            display_name: "Pressay Mac",
            app_variant: if cfg!(feature = "mas") {
                "mas"
            } else {
                "direct"
            },
            app_version: env!("CARGO_PKG_VERSION"),
        })
        .send()
        .await
        .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?;
    let bootstrap: BootstrapResponse = json(response).await?;
    if bootstrap.entitlement.revision == 0 {
        return Err(CloudFailure::new("cloud_entitlement_invalid"));
    }
    settings.pressay_cloud_account_id = Some(bootstrap.account_id);
    settings.pressay_cloud_device_id = Some(bootstrap.device.id);
    write_settings(app, settings);
    Ok(())
}

fn sync_context(settings: &AppSettings) -> Result<(&str, &str), CloudFailure> {
    let account_id = settings
        .pressay_cloud_account_id
        .as_deref()
        .ok_or_else(|| CloudFailure::new("cloud_not_connected"))?;
    let device_id = settings
        .pressay_cloud_device_id
        .as_deref()
        .ok_or_else(|| CloudFailure::new("cloud_not_connected"))?;
    if uuid::Uuid::parse_str(account_id).is_err() || uuid::Uuid::parse_str(device_id).is_err() {
        return Err(CloudFailure::new("cloud_account_invalid"));
    }
    Ok((account_id, device_id))
}

fn sync_device_keypair(account_id: &str) -> Result<([u8; 32], [u8; 32]), CloudFailure> {
    if let Some(private) = get_cloud_sync_device_key(account_id)
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?
    {
        let public = crate::sync_crypto::device_public_key(&private);
        return Ok((private, public));
    }
    let (private, public) = crate::sync_crypto::generate_device_keypair();
    set_cloud_sync_device_key(account_id, &private)
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?;
    Ok((private, public))
}

async fn sync_device_envelope(
    settings: &AppSettings,
    token: &str,
    device_id: &str,
) -> Result<Vec<u8>, CloudFailure> {
    let response: SyncDeviceEnvelopeResponse = json(
        client()
            .get(endpoint(
                settings,
                &format!("/v1/sync/devices/{device_id}/envelope"),
            )?)
            .bearer_auth(token)
            .send()
            .await
            .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?,
    )
    .await?;
    STANDARD
        .decode(response.encrypted_account_key)
        .map_err(|_| CloudFailure::new("cloud_sync_envelope_invalid"))
}

async fn load_sync_account_key(
    settings: &AppSettings,
    account_id: &str,
    device_id: &str,
    private: &[u8; 32],
) -> Result<[u8; 32], CloudFailure> {
    if let Some(account_key) = get_cloud_sync_account_key(account_id)
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?
    {
        return Ok(account_key);
    }
    let envelope = sync_device_envelope(settings, &access_token().await?, device_id).await?;
    let account_key = crate::sync_crypto::open_account_key(&envelope, private)
        .map_err(|_| CloudFailure::new("cloud_sync_envelope_invalid"))?;
    set_cloud_sync_account_key(account_id, &account_key)
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?;
    Ok(account_key)
}

async fn list_sync_devices(
    settings: &AppSettings,
    device_id: &str,
) -> Result<Vec<SyncDeviceResponse>, CloudFailure> {
    let mut url = endpoint(settings, "/v1/sync/devices")?;
    url.query_pairs_mut()
        .append_pair("approverDeviceId", device_id);
    let response: SyncDeviceListResponse = json(
        client()
            .get(url)
            .bearer_auth(access_token().await?)
            .send()
            .await
            .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?,
    )
    .await?;
    Ok(response.devices)
}

fn public_sync_devices(
    devices: Vec<SyncDeviceResponse>,
    current_device_id: &str,
) -> Result<Vec<CloudSyncDevice>, CloudFailure> {
    devices
        .into_iter()
        .map(|device| {
            if uuid::Uuid::parse_str(&device.id).is_err()
                || STANDARD
                    .decode(&device.public_key)
                    .map_or(true, |key| key.len() != 32)
            {
                return Err(CloudFailure::new("cloud_response_invalid"));
            }
            let status = match device.status.as_str() {
                "approved" => CloudSyncStatus::Ready,
                "pending" => CloudSyncStatus::PendingApproval,
                _ => return Err(CloudFailure::new("cloud_response_invalid")),
            };
            Ok(CloudSyncDevice {
                current: device.id == current_device_id,
                id: device.id,
                display_name: device.display_name,
                status,
            })
        })
        .collect()
}

pub async fn cloud_sync_snapshot(app: &AppHandle) -> Result<CloudSyncSnapshot, CloudFailure> {
    let settings = get_settings(app);
    let (account_id, device_id) = sync_context(&settings)?;
    let Some(private) = get_cloud_sync_device_key(account_id)
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?
    else {
        return Ok(CloudSyncSnapshot {
            status: CloudSyncStatus::NotConfigured,
            devices: Vec::new(),
        });
    };
    match load_sync_account_key(&settings, account_id, device_id, &private).await {
        Ok(_) => {
            let devices = list_sync_devices(&settings, device_id).await?;
            Ok(CloudSyncSnapshot {
                status: CloudSyncStatus::Ready,
                devices: public_sync_devices(devices, device_id)?,
            })
        }
        Err(error)
            if matches!(
                error.code.as_str(),
                "cloud_forbidden" | "sync_envelope_unavailable" | "sync_device_not_approved"
            ) =>
        {
            Ok(CloudSyncSnapshot {
                status: CloudSyncStatus::PendingApproval,
                devices: Vec::new(),
            })
        }
        Err(error) => Err(error),
    }
}

pub async fn initialize_cloud_sync(app: &AppHandle) -> Result<CloudSyncSnapshot, CloudFailure> {
    let settings = get_settings(app);
    let (account_id, device_id) = sync_context(&settings)?;
    let (private, public) = sync_device_keypair(account_id)?;
    let candidate_account_key = if get_cloud_sync_account_key(account_id)
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?
        .is_none()
    {
        Some(crate::sync_crypto::generate_account_key())
    } else {
        None
    };
    let sealed_candidate = candidate_account_key
        .as_ref()
        .map(|key| crate::sync_crypto::seal_account_key(key, &public))
        .transpose()
        .map_err(|_| CloudFailure::new("cloud_sync_encryption_failed"))?
        .map(|envelope| STANDARD.encode(envelope));
    let public_key = STANDARD.encode(public);
    let response: EnrollSyncDeviceResponse = json(
        client()
            .post(endpoint(&settings, "/v1/sync/devices/enroll")?)
            .bearer_auth(access_token().await?)
            .json(&EnrollSyncDeviceRequest {
                device_id,
                public_key: &public_key,
                encrypted_account_key: sealed_candidate.as_deref(),
            })
            .send()
            .await
            .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?,
    )
    .await?;
    match response.status.as_str() {
        "approved" => {
            load_sync_account_key(&settings, account_id, device_id, &private).await?;
            cloud_sync_snapshot(app).await
        }
        "pending" => Ok(CloudSyncSnapshot {
            status: CloudSyncStatus::PendingApproval,
            devices: Vec::new(),
        }),
        _ => Err(CloudFailure::new("cloud_response_invalid")),
    }
}

pub async fn approve_cloud_sync_device(
    app: &AppHandle,
    target_device_id: &str,
) -> Result<CloudSyncSnapshot, CloudFailure> {
    let settings = get_settings(app);
    let (account_id, current_device_id) = sync_context(&settings)?;
    let private = get_cloud_sync_device_key(account_id)
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?
        .ok_or_else(|| CloudFailure::new("cloud_sync_not_configured"))?;
    let account_key =
        load_sync_account_key(&settings, account_id, current_device_id, &private).await?;
    let devices = list_sync_devices(&settings, current_device_id).await?;
    let target = devices
        .iter()
        .find(|device| device.id == target_device_id && device.status == "pending")
        .ok_or_else(|| CloudFailure::new("cloud_sync_device_not_pending"))?;
    let target_public: [u8; 32] = STANDARD
        .decode(&target.public_key)
        .map_err(|_| CloudFailure::new("cloud_response_invalid"))?
        .try_into()
        .map_err(|_| CloudFailure::new("cloud_response_invalid"))?;
    let encrypted_account_key = STANDARD.encode(
        crate::sync_crypto::seal_account_key(&account_key, &target_public)
            .map_err(|_| CloudFailure::new("cloud_sync_encryption_failed"))?,
    );
    let response = client()
        .post(endpoint(
            &settings,
            &format!("/v1/sync/devices/{target_device_id}/approve"),
        )?)
        .bearer_auth(access_token().await?)
        .json(&ApproveSyncDeviceRequest {
            approver_device_id: current_device_id,
            encrypted_account_key: &encrypted_account_key,
        })
        .send()
        .await
        .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?;
    finish(response).await?;
    cloud_sync_snapshot(app).await
}

pub async fn create_cloud_sync_recovery_code(
    app: &AppHandle,
) -> Result<CloudSyncRecoveryCode, CloudFailure> {
    let settings = get_settings(app);
    let (account_id, device_id) = sync_context(&settings)?;
    let private = get_cloud_sync_device_key(account_id)
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?
        .ok_or_else(|| CloudFailure::new("cloud_sync_not_configured"))?;
    let account_key = load_sync_account_key(&settings, account_id, device_id, &private).await?;
    let (code, code_hash, encrypted_account_key) =
        crate::sync_crypto::create_recovery_envelope(&account_key)
            .map_err(|_| CloudFailure::new("cloud_sync_encryption_failed"))?;
    let response = client()
        .put(endpoint(&settings, "/v1/sync/recovery")?)
        .bearer_auth(access_token().await?)
        .json(&ConfigureSyncRecoveryRequest {
            device_id,
            code_hash: &STANDARD.encode(code_hash),
            encrypted_account_key: &STANDARD.encode(encrypted_account_key),
        })
        .send()
        .await
        .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?;
    finish(response).await?;
    Ok(CloudSyncRecoveryCode { code })
}

pub async fn recover_cloud_sync(
    app: &AppHandle,
    recovery_code: &str,
) -> Result<CloudSyncSnapshot, CloudFailure> {
    let settings = get_settings(app);
    let (account_id, device_id) = sync_context(&settings)?;
    let (_, public) = sync_device_keypair(account_id)?;
    let code_hash = crate::sync_crypto::recovery_code_hash(recovery_code)
        .map_err(|_| CloudFailure::new("cloud_sync_recovery_code_invalid"))?;
    let code_hash = STANDARD.encode(code_hash);
    let public_key = STANDARD.encode(public);
    let recovery: SyncRecoveryEnvelopeResponse = json(
        client()
            .post(endpoint(&settings, "/v1/sync/recovery/begin")?)
            .bearer_auth(access_token().await?)
            .json(&BeginSyncRecoveryRequest {
                device_id,
                public_key: &public_key,
                code_hash: &code_hash,
            })
            .send()
            .await
            .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?,
    )
    .await?;
    let recovery_envelope = STANDARD
        .decode(recovery.encrypted_account_key)
        .map_err(|_| CloudFailure::new("cloud_sync_envelope_invalid"))?;
    let mut account_key =
        crate::sync_crypto::open_recovery_envelope(recovery_code, &recovery_envelope)
            .map_err(|_| CloudFailure::new("cloud_sync_recovery_code_invalid"))?;
    let encrypted_account_key = STANDARD.encode(
        crate::sync_crypto::seal_account_key(&account_key, &public)
            .map_err(|_| CloudFailure::new("cloud_sync_encryption_failed"))?,
    );
    set_cloud_sync_account_key(account_id, &account_key)
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?;
    account_key.fill(0);
    let response = client()
        .post(endpoint(&settings, "/v1/sync/recovery/complete")?)
        .bearer_auth(access_token().await?)
        .json(&CompleteSyncRecoveryRequest {
            device_id,
            code_hash: &code_hash,
            encrypted_account_key: &encrypted_account_key,
        })
        .send()
        .await
        .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?;
    finish(response).await?;
    cloud_sync_snapshot(app).await
}

pub async fn append_sync_changes(
    settings: &AppSettings,
    device_id: &str,
    changes: &[SyncChangeInput],
) -> Result<(u64, u64, u64), CloudFailure> {
    if changes.is_empty() || changes.len() > 100 {
        return Err(CloudFailure::new("cloud_sync_batch_invalid"));
    }
    let response: AppendSyncChangesResponse = json(
        client()
            .post(endpoint(settings, "/v1/sync/changes")?)
            .bearer_auth(access_token().await?)
            .json(&AppendSyncChangesRequest { device_id, changes })
            .send()
            .await
            .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?,
    )
    .await?;
    Ok((response.accepted, response.conflicts, response.cursor))
}

pub async fn fetch_sync_changes(
    settings: &AppSettings,
    device_id: &str,
    after: u64,
) -> Result<SyncChangesResponse, CloudFailure> {
    let mut url = endpoint(settings, "/v1/sync/changes")?;
    url.query_pairs_mut()
        .append_pair("deviceId", device_id)
        .append_pair("after", &after.to_string())
        .append_pair("limit", "200");
    json(
        client()
            .get(url)
            .bearer_auth(access_token().await?)
            .send()
            .await
            .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?,
    )
    .await
}

pub async fn account_snapshot(app: &AppHandle) -> Result<CloudAccountSnapshot, CloudFailure> {
    let mut settings = get_settings(app);
    if settings.pressay_cloud_device_id.is_none() {
        let has_session = stored_oauth_token_set()?.is_some()
            || get_cloud_bearer_token()
                .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?
                .is_some();
        if !has_session {
            clear_account_snapshot_cache();
            return Ok(CloudAccountSnapshot {
                connected: false,
                account_id: None,
                email: None,
                device_id: None,
                entitlement: None,
                usage: None,
            });
        }
        bootstrap_device(app).await?;
        settings = get_settings(app);
    }
    let device_id = settings
        .pressay_cloud_device_id
        .as_deref()
        .ok_or_else(|| CloudFailure::new("cloud_account_invalid"))?;
    let online = async {
        let token = access_token().await?;
        let me: MeResponse = json(
            client()
                .get(endpoint(&settings, "/v1/me")?)
                .bearer_auth(&token)
                .send()
                .await
                .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?,
        )
        .await?;
        let entitlements: EntitlementResponse = json(
            client()
                .get(endpoint(&settings, "/v1/entitlements")?)
                .bearer_auth(token)
                .header("x-device-id", device_id)
                .send()
                .await
                .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?,
        )
        .await?;
        let verifier = entitlement_verifier_config()?;
        if me.account_id
            != settings
                .pressay_cloud_account_id
                .as_deref()
                .unwrap_or_default()
            || entitlements.signed_snapshot.key_id != verifier.key_id
        {
            return Err(CloudFailure::new("cloud_account_mismatch"));
        }
        let (verified_entitlement, verified_usage) = verify_entitlement_token(
            &entitlements.signed_snapshot.token,
            &settings,
            chrono::Utc::now().timestamp(),
        )?;
        if verified_entitlement.tier != entitlements.entitlement.tier
            || verified_entitlement.source != entitlements.entitlement.source
            || verified_entitlement.revision != entitlements.entitlement.revision
            || verified_usage.transcription.limit_seconds
                != entitlements.usage.transcription.limit_seconds
            || verified_usage.transformations.limit != entitlements.usage.transformations.limit
        {
            return Err(CloudFailure::new("cloud_entitlement_invalid"));
        }
        let _ = &entitlements.signed_snapshot.expires_at;
        set_cloud_entitlement_snapshot(&entitlements.signed_snapshot.token)
            .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?;
        let _ = me.entitlement;
        Ok(CloudAccountSnapshot {
            connected: true,
            account_id: Some(me.account_id),
            email: Some(me.email),
            device_id: Some(device_id.to_string()),
            entitlement: Some(entitlements.entitlement),
            usage: Some(entitlements.usage),
        })
    }
    .await;

    match online {
        Ok(snapshot) => {
            remember_account_snapshot(&snapshot);
            Ok(snapshot)
        }
        Err(error)
            if matches!(
                error.code.as_str(),
                "cloud_network_unavailable" | "cloud_unavailable"
            ) =>
        {
            cached_account_snapshot(&settings)
        }
        Err(error) => Err(error),
    }
}

pub async fn restore_app_store_transaction(
    app: &AppHandle,
    signed_transaction: &str,
    transaction_id: &str,
) -> Result<CloudAccountSnapshot, CloudFailure> {
    if signed_transaction.len() < 64
        || signed_transaction.len() > 250_000
        || signed_transaction.split('.').count() != 3
        || transaction_id.is_empty()
        || transaction_id.len() > 32
        || !transaction_id.bytes().all(|value| value.is_ascii_digit())
    {
        return Err(CloudFailure::new("storekit_transaction_invalid"));
    }
    let settings = get_settings(app);
    let response: RestoreAppStoreResponse = json(
        client()
            .post(endpoint(&settings, "/v1/billing/restore-app-store")?)
            .bearer_auth(access_token().await?)
            .header(
                "idempotency-key",
                format!("app-store-transaction-{transaction_id}"),
            )
            .json(&RestoreAppStoreRequest { signed_transaction })
            .send()
            .await
            .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?,
    )
    .await?;
    if !response.restored {
        return Err(CloudFailure::new("storekit_restore_failed"));
    }
    account_snapshot(app).await
}

pub async fn sign_out(app: &AppHandle) -> Result<(), CloudFailure> {
    let settings = get_settings(app);
    if let Ok(token) = access_token().await {
        let _ = client()
            .post(endpoint(&settings, "/v1/auth/sign-out")?)
            .bearer_auth(token)
            .send()
            .await;
    }
    delete_cloud_bearer_token().map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?;
    delete_cloud_oauth_token_set().map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?;
    delete_cloud_entitlement_snapshot()
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?;
    let mut settings = get_settings(app);
    settings.pressay_cloud_account_id = None;
    settings.pressay_cloud_device_id = None;
    write_settings(app, settings);
    clear_account_snapshot_cache();
    Ok(())
}

pub async fn delete_account(app: &AppHandle) -> Result<(), CloudFailure> {
    let settings = get_settings(app);
    let account_id = settings.pressay_cloud_account_id.clone();
    let response = client()
        .delete(endpoint(&settings, "/v1/me")?)
        .bearer_auth(access_token().await?)
        .send()
        .await
        .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?;
    finish(response).await?;
    sign_out(app).await?;
    if let Some(account_id) = account_id {
        delete_cloud_sync_keys(&account_id)
            .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?;
    }
    Ok(())
}

pub async fn transform(
    settings: &AppSettings,
    request: CloudTransformationRequest<'_>,
    idempotency_key: &str,
) -> Result<CloudTransformationResponse, CloudFailure> {
    let response = client()
        .post(endpoint(settings, "/v1/cloud/transformations")?)
        .bearer_auth(access_token().await?)
        .header("idempotency-key", idempotency_key)
        .json(&request)
        .send()
        .await
        .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?;
    let response: CloudTransformationResponse = json(response).await?;
    if response.model_alias != "pressay-transform-v1"
        || response.text.trim().is_empty()
        || response.operation_id.trim().is_empty()
    {
        return Err(CloudFailure::new("cloud_response_invalid"));
    }
    Ok(response)
}

pub async fn transcribe_audio(
    settings: &AppSettings,
    device_id: &str,
    wav: Vec<u8>,
    language: Option<&str>,
    idempotency_key: &str,
) -> Result<CloudTranscriptionResponse, CloudFailure> {
    if wav.is_empty() || wav.len() > 4_000_000 {
        return Err(CloudFailure::new("cloud_audio_too_large"));
    }
    let audio = reqwest::multipart::Part::bytes(wav)
        .file_name("pressay-recording.wav")
        .mime_str("audio/wav")
        .map_err(|_| CloudFailure::new("cloud_audio_invalid"))?;
    let mut form = reqwest::multipart::Form::new()
        .text("deviceId", device_id.to_string())
        .text("contentTransferAcknowledged", "true")
        .part("audio", audio);
    if let Some(language) = language.filter(|value| !value.trim().is_empty()) {
        form = form.text("language", language.to_string());
    }
    let response = client()
        .post(endpoint(settings, "/v1/cloud/transcriptions")?)
        .bearer_auth(access_token().await?)
        .header("idempotency-key", idempotency_key)
        .multipart(form)
        .send()
        .await
        .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?;
    let response: CloudTranscriptionResponse = json(response).await?;
    if response.model_alias != "pressay-transcribe-v1"
        || response.text.trim().is_empty()
        || response.operation_id.trim().is_empty()
        || !response.duration_seconds.is_finite()
        || response.duration_seconds <= 0.0
    {
        return Err(CloudFailure::new("cloud_response_invalid"));
    }
    Ok(response)
}

fn auth_callback_parts(url: &Url) -> Result<AuthCallback, CloudFailure> {
    if url.scheme() != "pressay" || url.host_str() != Some("oauth") || url.path() != "/callback" {
        return Err(CloudFailure::new("cloud_auth_callback_invalid"));
    }
    let mut code = None;
    let mut query_state = None;
    for (key, value) in url.query_pairs() {
        match key.as_ref() {
            "code" if code.is_none() => code = Some(value.into_owned()),
            "state" if query_state.is_none() => query_state = Some(value.into_owned()),
            _ => {}
        }
    }
    if let (Some(code), Some(state)) = (code, query_state) {
        return Ok(AuthCallback::OAuth { code, state });
    }

    let fragment = url.fragment().unwrap_or_default();
    let mut token = None;
    let mut state = None;
    for (key, value) in form_urlencoded::parse(fragment.as_bytes()) {
        match key.as_ref() {
            "token" if token.is_none() => token = Some(value),
            "state" if state.is_none() => state = Some(value),
            _ => {}
        }
    }
    let token = token.ok_or_else(|| CloudFailure::new("cloud_auth_token_missing"))?;
    let state = state.ok_or_else(|| CloudFailure::new("cloud_auth_state_missing"))?;
    Ok(AuthCallback::Legacy {
        token: token.into_owned(),
        state: state.into_owned(),
    })
}

fn auth_error_state(url: &Url) -> Result<String, CloudFailure> {
    if url.scheme() != "pressay"
        || url.host_str() != Some("oauth")
        || !matches!(url.path(), "/error" | "/callback")
        || (url.path() == "/callback" && !url.query_pairs().any(|(key, _)| key == "error"))
    {
        return Err(CloudFailure::new("cloud_auth_callback_invalid"));
    }
    url.query_pairs()
        .find_map(|(key, value)| (key == "state").then(|| value.into_owned()))
        .ok_or_else(|| CloudFailure::new("cloud_auth_state_missing"))
}

pub fn handle_deep_link(app: AppHandle, url: Url) {
    let is_error = url.host_str() == Some("oauth")
        && (url.path() == "/error"
            || (url.path() == "/callback" && url.query_pairs().any(|(key, _)| key == "error")));
    let parsed = if is_error {
        auth_error_state(&url).and_then(|state| {
            let _ = app.state::<CloudAuthRuntime>().consume(&state)?;
            Err(CloudFailure::new("cloud_auth_provider_failed"))
        })
    } else {
        auth_callback_parts(&url)
    };
    if parsed.is_ok() {
        let _ = app.emit(
            "cloud-auth-state-changed",
            CloudAuthEvent {
                status: CloudAuthEventStatus::Exchanging,
                error_code: None,
            },
        );
    }
    tauri::async_runtime::spawn(async move {
        let result = async {
            match parsed? {
                AuthCallback::OAuth { code, state } => {
                    let verifier = app
                        .state::<CloudAuthRuntime>()
                        .consume(&state)?
                        .ok_or_else(|| CloudFailure::new("cloud_auth_state_mismatch"))?;
                    exchange_oauth_code(&code, &verifier).await?;
                }
                AuthCallback::Legacy { token, state } => {
                    let verifier = app.state::<CloudAuthRuntime>().consume(&state)?;
                    if verifier.is_some() {
                        return Err(CloudFailure::new("cloud_auth_state_mismatch"));
                    }
                    let settings = get_settings(&app);
                    exchange_one_time_token(&settings, &token).await?;
                }
            }
            let _ = app.emit(
                "cloud-auth-state-changed",
                CloudAuthEvent {
                    status: CloudAuthEventStatus::Bootstrapping,
                    error_code: None,
                },
            );
            if let Err(error) = bootstrap_device(&app).await {
                let _ = delete_cloud_bearer_token();
                let _ = delete_cloud_oauth_token_set();
                return Err(error);
            }
            Ok::<(), CloudFailure>(())
        }
        .await;

        let event = match result {
            Ok(()) => CloudAuthEvent {
                status: CloudAuthEventStatus::Connected,
                error_code: None,
            },
            Err(error) => {
                log::warn!("Cloud authentication failed with code {}", error.code);
                CloudAuthEvent {
                    status: CloudAuthEventStatus::Failed,
                    error_code: Some(error.code),
                }
            }
        };
        let _ = app.emit("cloud-auth-state-changed", event);
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};

    #[test]
    fn api_error_body_accepts_modern_and_legacy_envelopes() {
        let modern: ApiErrorBody =
            serde_json::from_str(r#"{"error":{"code":"account_bootstrap_failed"}}"#).unwrap();
        assert_eq!(modern.error.code(), "account_bootstrap_failed");

        let legacy: ApiErrorBody =
            serde_json::from_str(r#"{"error":"account_bootstrap_failed"}"#).unwrap();
        assert_eq!(legacy.error.code(), "account_bootstrap_failed");
    }

    #[test]
    fn release_channels_pin_distinct_entitlement_verifiers() {
        let beta = default_entitlement_verifier_config("2.0.0-beta.3");
        let stable = default_entitlement_verifier_config("2.0.0");

        assert_eq!(beta.key_id, STAGING_ENTITLEMENT_KEY_ID);
        assert_eq!(beta.public_key, STAGING_ENTITLEMENT_PUBLIC_KEY);
        assert_eq!(stable.key_id, PRODUCTION_ENTITLEMENT_KEY_ID);
        assert_eq!(stable.public_key, PRODUCTION_ENTITLEMENT_PUBLIC_KEY);
        assert_ne!(beta.key_id, stable.key_id);
        assert_ne!(beta.public_key, stable.public_key);
    }

    fn signed_entitlement_fixture(
        signing_key: &SigningKey,
        account_id: &str,
        device_id: &str,
        issued_at: i64,
        expires_at: i64,
    ) -> String {
        let verifier = entitlement_verifier_config().unwrap();
        signed_entitlement_fixture_with_config(
            signing_key,
            account_id,
            device_id,
            issued_at,
            expires_at,
            verifier,
        )
    }

    fn signed_entitlement_fixture_with_config(
        signing_key: &SigningKey,
        account_id: &str,
        device_id: &str,
        issued_at: i64,
        expires_at: i64,
        verifier: EntitlementVerifierConfig,
    ) -> String {
        let header = URL_SAFE_NO_PAD.encode(
            serde_json::to_vec(&serde_json::json!({
                "alg": "EdDSA",
                "kid": verifier.key_id,
                "typ": "JWT"
            }))
            .unwrap(),
        );
        let claims = URL_SAFE_NO_PAD.encode(
            serde_json::to_vec(&serde_json::json!({
                "tier": "pro",
                "source": "trial",
                "revision": 3,
                "device_id": device_id,
                "online_valid_until": expires_at - 60,
                "offline_grace_until": expires_at,
                "usage": {
                    "period_start": "2026-08-01",
                    "transcription_seconds_used": 120,
                    "transcription_seconds_limit": 36000,
                    "transformations_used": 7,
                    "transformations_limit": 2000
                },
                "iss": verifier.issuer,
                "aud": ["app.pressay.desktop", "fr.yodev.pressay"],
                "sub": account_id,
                "iat": issued_at,
                "exp": expires_at
            }))
            .unwrap(),
        );
        let input = format!("{header}.{claims}");
        let signature = URL_SAFE_NO_PAD.encode(signing_key.sign(input.as_bytes()).to_bytes());
        format!("{input}.{signature}")
    }

    #[test]
    fn beta_build_defaults_to_isolated_staging() {
        let expected = option_env!("PRESSAY_CLOUD_API_URL")
            .unwrap_or("https://pressay-cloud-staging.vercel.app");
        assert_eq!(
            crate::settings::get_default_settings().pressay_cloud_api_url,
            expected
        );
    }

    #[test]
    fn bearer_hosts_are_allowlisted() {
        assert!(validate_base_url("https://api.press-say.app").is_ok());
        assert!(validate_base_url("https://api-staging.press-say.app").is_ok());
        assert!(validate_base_url("https://pressay-cloud-staging.vercel.app").is_ok());
        assert!(validate_base_url("https://attacker.example").is_err());
        assert!(validate_base_url("https://api.press-say.app.attacker.example").is_err());
    }

    #[test]
    fn apple_auth_starts_in_the_browser_on_the_configured_api() {
        let settings = crate::settings::get_default_settings();
        let url = apple_browser_login_url(&settings, "expected-state-value").unwrap();
        assert_eq!(url.path(), "/v1/desktop-auth/social/apple");
        assert_eq!(
            url.query_pairs()
                .find_map(|(key, value)| (key == "state").then(|| value.into_owned())),
            Some("expected-state-value".to_string())
        );
        assert_eq!(
            url.host_str(),
            validate_base_url(&settings.pressay_cloud_api_url)
                .unwrap()
                .host_str()
        );
        assert!(!uses_native_oauth_pkce(CloudAuthProvider::Apple));
        assert!(uses_native_oauth_pkce(CloudAuthProvider::Google));
    }

    #[test]
    fn callback_accepts_oauth_query_and_legacy_fragment_on_exact_scheme_host_path() {
        let oauth = Url::parse(
            "pressay://oauth/callback?code=authorization-code&state=expected-state-value",
        )
        .unwrap();
        assert_eq!(
            auth_callback_parts(&oauth).unwrap(),
            AuthCallback::OAuth {
                code: "authorization-code".to_string(),
                state: "expected-state-value".to_string(),
            }
        );
        let legacy = Url::parse(
            "pressay://oauth/callback#token=one-time-token-value&state=expected-state-value",
        )
        .unwrap();
        assert_eq!(
            auth_callback_parts(&legacy).unwrap(),
            AuthCallback::Legacy {
                token: "one-time-token-value".to_string(),
                state: "expected-state-value".to_string(),
            }
        );
        assert!(auth_callback_parts(
            &Url::parse("https://oauth/callback#token=x&state=y").unwrap()
        )
        .is_err());
        assert!(
            auth_callback_parts(&Url::parse("pressay://oauth/other#token=x&state=y").unwrap())
                .is_err()
        );
    }

    #[test]
    fn error_callback_accepts_only_the_expected_state_location() {
        let valid = Url::parse("pressay://oauth/error?state=expected-state-value").unwrap();
        assert_eq!(auth_error_state(&valid).unwrap(), "expected-state-value");
        let oauth_error =
            Url::parse("pressay://oauth/callback?error=access_denied&state=expected-state-value")
                .unwrap();
        assert_eq!(
            auth_error_state(&oauth_error).unwrap(),
            "expected-state-value"
        );
        assert!(auth_error_state(
            &Url::parse("pressay://oauth/error#state=expected-state-value").unwrap()
        )
        .is_err());
    }

    #[test]
    fn pending_state_is_single_use() {
        let runtime = CloudAuthRuntime::default();
        let state = runtime.begin().unwrap();
        assert!(runtime.consume(&state).is_ok());
        assert!(runtime.consume(&state).is_err());
    }

    #[test]
    fn clearing_pending_state_cancels_the_login() {
        let runtime = CloudAuthRuntime::default();
        let state = runtime.begin().unwrap();
        runtime.clear();
        assert!(runtime.consume(&state).is_err());
    }

    #[test]
    fn oauth_pending_state_carries_a_pkce_verifier_once() {
        let runtime = CloudAuthRuntime::default();
        let (state, verifier) = runtime.begin_oauth().unwrap();
        assert!((43..=128).contains(&verifier.len()));
        assert_eq!(runtime.consume(&state).unwrap(), Some(verifier));
        assert!(runtime.consume(&state).is_err());
    }

    #[test]
    fn unsafe_backend_codes_are_redacted() {
        assert_eq!(safe_error_code("quota_exceeded"), "quota_exceeded");
        assert_eq!(
            safe_error_code("provider said user@example.com"),
            "cloud_request_failed"
        );
    }

    #[test]
    fn signed_entitlement_is_bound_to_account_device_audience_and_expiry() {
        let signing_key = SigningKey::from_bytes(&[7_u8; 32]);
        let mut settings = AppSettings::default();
        settings.pressay_cloud_account_id = Some("account-id".to_string());
        settings.pressay_cloud_device_id = Some("device-id".to_string());
        let token =
            signed_entitlement_fixture(&signing_key, "account-id", "device-id", 1_000, 2_000);

        let (entitlement, usage) = verify_entitlement_token_with_key(
            &token,
            &settings,
            1_100,
            &signing_key.verifying_key().to_bytes(),
        )
        .unwrap();
        assert_eq!(entitlement.tier, EntitlementTier::Pro);
        assert_eq!(entitlement.source, EntitlementSource::Trial);
        assert_eq!(usage.transformations.limit, 2_000);

        let mut wrong_device = settings.clone();
        wrong_device.pressay_cloud_device_id = Some("another-device".to_string());
        assert!(verify_entitlement_token_with_key(
            &token,
            &wrong_device,
            1_100,
            &signing_key.verifying_key().to_bytes(),
        )
        .is_err());
        assert!(verify_entitlement_token_with_key(
            &token,
            &settings,
            2_000,
            &signing_key.verifying_key().to_bytes(),
        )
        .is_err());
    }

    #[test]
    fn entitlement_from_another_release_channel_is_rejected() {
        let signing_key = SigningKey::from_bytes(&[11_u8; 32]);
        let mut settings = AppSettings::default();
        settings.pressay_cloud_account_id = Some("account-id".to_string());
        settings.pressay_cloud_device_id = Some("device-id".to_string());
        let staging = default_entitlement_verifier_config("2.0.0-beta.3");
        let production = default_entitlement_verifier_config("2.0.0");
        let token = signed_entitlement_fixture_with_config(
            &signing_key,
            "account-id",
            "device-id",
            1_000,
            2_000,
            staging,
        );

        assert!(verify_entitlement_token_with_config(
            &token,
            &settings,
            1_100,
            &signing_key.verifying_key().to_bytes(),
            production,
        )
        .is_err());
    }

    #[test]
    fn signed_entitlement_rejects_tampering() {
        let signing_key = SigningKey::from_bytes(&[9_u8; 32]);
        let mut settings = AppSettings::default();
        settings.pressay_cloud_account_id = Some("account-id".to_string());
        settings.pressay_cloud_device_id = Some("device-id".to_string());
        let token =
            signed_entitlement_fixture(&signing_key, "account-id", "device-id", 1_000, 2_000);
        let (unsigned, signature) = token.rsplit_once('.').unwrap();
        let replacement = if signature.starts_with('A') { 'B' } else { 'A' };
        let tampered = format!("{unsigned}.{replacement}{}", &signature[1..]);
        assert!(verify_entitlement_token_with_key(
            &tampered,
            &settings,
            1_100,
            &signing_key.verifying_key().to_bytes(),
        )
        .is_err());
    }
}
