use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use reqwest::{Client, Response, StatusCode, Url};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use specta::Type;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter, Manager};
use url::form_urlencoded;

use crate::secrets::{
    delete_cloud_bearer_token, delete_cloud_entitlement_snapshot, delete_cloud_sync_keys,
    get_cloud_bearer_token, get_cloud_entitlement_snapshot, get_cloud_sync_account_key,
    get_cloud_sync_device_key, set_cloud_bearer_token, set_cloud_entitlement_snapshot,
    set_cloud_sync_account_key, set_cloud_sync_device_key,
};
use crate::settings::{get_settings, write_settings, AppSettings};

const AUTH_STATE_TTL: Duration = Duration::from_secs(15 * 60);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(45);
const MAX_ERROR_CODE_LEN: usize = 80;
const ENTITLEMENT_KEY_ID: &str = "pressay-entitlement-2026-01";
const ENTITLEMENT_PUBLIC_KEY: &str = "gj3woVSEMEiNemiZKdA28oEvMrLL9iQPbiMPr_B-plQ";
const ENTITLEMENT_ISSUER: &str = "https://api.press-say.app";

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
    Connected,
    Failed,
}

#[derive(Debug)]
struct PendingAuth {
    state: String,
    created_at: Instant,
}

#[derive(Default)]
pub struct CloudAuthRuntime {
    pending: Mutex<Option<PendingAuth>>,
}

impl CloudAuthRuntime {
    pub fn begin(&self) -> Result<String, CloudFailure> {
        let state = URL_SAFE_NO_PAD.encode(crate::history_crypto::generate_master_key());
        let mut pending = self
            .pending
            .lock()
            .map_err(|_| CloudFailure::new("cloud_auth_state_unavailable"))?;
        *pending = Some(PendingAuth {
            state: state.clone(),
            created_at: Instant::now(),
        });
        Ok(state)
    }

    fn consume(&self, state: &str) -> Result<(), CloudFailure> {
        let mut pending = self
            .pending
            .lock()
            .map_err(|_| CloudFailure::new("cloud_auth_state_unavailable"))?;
        let valid = pending.as_ref().is_some_and(|candidate| {
            candidate.created_at.elapsed() <= AUTH_STATE_TTL && candidate.state == state
        });
        pending.take();
        if valid {
            Ok(())
        } else {
            Err(CloudFailure::new("cloud_auth_state_mismatch"))
        }
    }

    pub fn clear(&self) {
        if let Ok(mut pending) = self.pending.lock() {
            pending.take();
        }
    }
}

#[derive(Deserialize)]
struct ApiErrorBody {
    error: ApiErrorValue,
}

#[derive(Deserialize)]
struct ApiErrorValue {
    code: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct MagicLinkRequest<'a> {
    email: &'a str,
    callback_url: &'a str,
    error_callback_url: &'a str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SocialLoginRequest<'a> {
    provider: CloudAuthProvider,
    callback_url: &'a str,
    error_callback_url: &'a str,
    disable_redirect: bool,
}

#[derive(Deserialize)]
struct SocialLoginResponse {
    url: String,
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

async fn finish(response: Response) -> Result<Response, CloudFailure> {
    if response.status().is_success() {
        return Ok(response);
    }
    let status = response.status();
    let code = response
        .json::<ApiErrorBody>()
        .await
        .ok()
        .map(|body| safe_error_code(&body.error.code))
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

fn bearer() -> Result<String, CloudFailure> {
    get_cloud_bearer_token()
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?
        .ok_or_else(|| CloudFailure::new("cloud_not_connected"))
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
    let public_key_bytes: [u8; 32] = URL_SAFE_NO_PAD
        .decode(ENTITLEMENT_PUBLIC_KEY)
        .map_err(|_| CloudFailure::new("cloud_entitlement_invalid"))?
        .try_into()
        .map_err(|_| CloudFailure::new("cloud_entitlement_invalid"))?;
    verify_entitlement_token_with_key(token, settings, now_seconds, &public_key_bytes)
}

fn verify_entitlement_token_with_key(
    token: &str,
    settings: &AppSettings,
    now_seconds: i64,
    public_key_bytes: &[u8; 32],
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
    if header.alg != "EdDSA" || header.kid != ENTITLEMENT_KEY_ID || header.typ != "JWT" {
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
        "app.pressay.desktop.mas"
    } else {
        "app.pressay.desktop"
    };
    if claims.iss != ENTITLEMENT_ISSUER
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

fn cached_account_snapshot(settings: &AppSettings) -> Result<CloudAccountSnapshot, CloudFailure> {
    let token = get_cloud_entitlement_snapshot()
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?
        .ok_or_else(|| CloudFailure::new("cloud_network_unavailable"))?;
    let (entitlement, usage) =
        verify_entitlement_token(&token, settings, chrono::Utc::now().timestamp())?;
    Ok(CloudAccountSnapshot {
        connected: true,
        account_id: settings.pressay_cloud_account_id.clone(),
        email: None,
        device_id: settings.pressay_cloud_device_id.clone(),
        entitlement: Some(entitlement),
        usage: Some(usage),
    })
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
    let response = client()
        .get(endpoint(settings, "/v1/desktop-auth/config")?)
        .send()
        .await
        .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?;
    json(response).await
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
) -> Result<String, CloudFailure> {
    let config = get_auth_config(settings).await?;
    if !config.providers.contains(&provider) {
        return Err(CloudFailure::new("cloud_social_login_unavailable"));
    }
    let (callback_url, error_callback_url) = callback_urls(&config, state)?;
    let response = client()
        .post(endpoint(settings, "/v1/auth/sign-in/social")?)
        .json(&SocialLoginRequest {
            provider,
            callback_url: &callback_url,
            error_callback_url: &error_callback_url,
            disable_redirect: true,
        })
        .send()
        .await
        .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?;
    let response: SocialLoginResponse = json(response).await?;
    let authorization_url =
        Url::parse(&response.url).map_err(|_| CloudFailure::new("cloud_social_url_invalid"))?;
    let host = authorization_url.host_str().unwrap_or_default();
    if authorization_url.scheme() != "https"
        || !matches!(host, "accounts.google.com" | "appleid.apple.com")
    {
        return Err(CloudFailure::new("cloud_social_url_not_allowed"));
    }
    Ok(authorization_url.to_string())
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
    let token = bearer()?;
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
    let envelope = sync_device_envelope(settings, &bearer()?, device_id).await?;
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
            .bearer_auth(bearer()?)
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
            .bearer_auth(bearer()?)
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
        .bearer_auth(bearer()?)
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
            .bearer_auth(bearer()?)
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
            .bearer_auth(bearer()?)
            .send()
            .await
            .map_err(|_| CloudFailure::new("cloud_network_unavailable"))?,
    )
    .await
}

pub async fn account_snapshot(app: &AppHandle) -> Result<CloudAccountSnapshot, CloudFailure> {
    let settings = get_settings(app);
    let Some(device_id) = settings.pressay_cloud_device_id.as_deref() else {
        return Ok(CloudAccountSnapshot {
            connected: false,
            account_id: None,
            email: None,
            device_id: None,
            entitlement: None,
            usage: None,
        });
    };
    let online = async {
        let token = bearer()?;
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
        if me.account_id
            != settings
                .pressay_cloud_account_id
                .as_deref()
                .unwrap_or_default()
            || entitlements.signed_snapshot.key_id != ENTITLEMENT_KEY_ID
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
        Ok(snapshot) => Ok(snapshot),
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

pub async fn sign_out(app: &AppHandle) -> Result<(), CloudFailure> {
    let settings = get_settings(app);
    if let Ok(token) = bearer() {
        let _ = client()
            .post(endpoint(&settings, "/v1/auth/sign-out")?)
            .bearer_auth(token)
            .send()
            .await;
    }
    delete_cloud_bearer_token().map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?;
    delete_cloud_entitlement_snapshot()
        .map_err(|_| CloudFailure::new("cloud_keychain_unavailable"))?;
    let mut settings = get_settings(app);
    settings.pressay_cloud_account_id = None;
    settings.pressay_cloud_device_id = None;
    write_settings(app, settings);
    Ok(())
}

pub async fn delete_account(app: &AppHandle) -> Result<(), CloudFailure> {
    let settings = get_settings(app);
    let account_id = settings.pressay_cloud_account_id.clone();
    let response = client()
        .delete(endpoint(&settings, "/v1/me")?)
        .bearer_auth(bearer()?)
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
        .bearer_auth(bearer()?)
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
        .bearer_auth(bearer()?)
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

fn auth_callback_parts(url: &Url) -> Result<(String, String), CloudFailure> {
    if url.scheme() != "pressay" || url.host_str() != Some("oauth") || url.path() != "/callback" {
        return Err(CloudFailure::new("cloud_auth_callback_invalid"));
    }
    let fragment = url
        .fragment()
        .ok_or_else(|| CloudFailure::new("cloud_auth_callback_invalid"))?;
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
    Ok((token.into_owned(), state.into_owned()))
}

fn auth_error_state(url: &Url) -> Result<String, CloudFailure> {
    if url.scheme() != "pressay" || url.host_str() != Some("oauth") || url.path() != "/error" {
        return Err(CloudFailure::new("cloud_auth_callback_invalid"));
    }
    url.query_pairs()
        .find_map(|(key, value)| (key == "state").then(|| value.into_owned()))
        .ok_or_else(|| CloudFailure::new("cloud_auth_state_missing"))
}

pub fn handle_deep_link(app: AppHandle, url: Url) {
    let parsed = if url.host_str() == Some("oauth") && url.path() == "/error" {
        auth_error_state(&url).and_then(|state| {
            app.state::<CloudAuthRuntime>().consume(&state)?;
            Err(CloudFailure::new("cloud_auth_provider_failed"))
        })
    } else {
        auth_callback_parts(&url)
    };
    tauri::async_runtime::spawn(async move {
        let result = async {
            let (token, state) = parsed?;
            app.state::<CloudAuthRuntime>().consume(&state)?;
            let settings = get_settings(&app);
            exchange_one_time_token(&settings, &token).await?;
            if let Err(error) = bootstrap_device(&app).await {
                let _ = delete_cloud_bearer_token();
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

    fn signed_entitlement_fixture(
        signing_key: &SigningKey,
        account_id: &str,
        device_id: &str,
        issued_at: i64,
        expires_at: i64,
    ) -> String {
        let header = URL_SAFE_NO_PAD.encode(
            serde_json::to_vec(&serde_json::json!({
                "alg": "EdDSA",
                "kid": ENTITLEMENT_KEY_ID,
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
                "iss": ENTITLEMENT_ISSUER,
                "aud": ["app.pressay.desktop", "app.pressay.desktop.mas"],
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
        assert!(validate_base_url("https://pressay-cloud-staging.vercel.app").is_ok());
        assert!(validate_base_url("https://attacker.example").is_err());
        assert!(validate_base_url("https://api.press-say.app.attacker.example").is_err());
    }

    #[test]
    fn callback_requires_exact_scheme_host_path_and_fragment_fields() {
        let valid = Url::parse(
            "pressay://oauth/callback#token=one-time-token-value&state=expected-state-value",
        )
        .unwrap();
        assert_eq!(
            auth_callback_parts(&valid).unwrap(),
            (
                "one-time-token-value".to_string(),
                "expected-state-value".to_string()
            )
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
