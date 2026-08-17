use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use specta::Type;
use std::collections::{BTreeMap, HashSet};
use std::fs::OpenOptions;
use std::io::Write;
#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;
use tauri::AppHandle;

use crate::cloud::{self, CloudFailure, SyncChangeInput, SyncChangeOutput, SyncObjectType};
use crate::productivity::{
    is_builtin_mode_id, validate_dictionary, validate_mode, validate_profile, AppProfile,
    DictionaryEntry, PressayMode,
};
use crate::secrets::{get_cloud_sync_account_key, get_cloud_sync_device_key};
use crate::settings::{get_settings, write_settings, AppSettings};

const STATE_SCHEMA_VERSION: u32 = 1;
const ENVELOPE_VERSION: u8 = 1;
const MAX_ENVELOPE_BYTES: usize = 1_048_576;

#[derive(Serialize, Deserialize, Debug, Clone, Default)]
struct SyncEntryState {
    revision: u64,
    hash: String,
    tombstone: bool,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct SyncLocalState {
    schema_version: u32,
    account_id: String,
    cursor: u64,
    entries: BTreeMap<String, SyncEntryState>,
}

impl SyncLocalState {
    fn new(account_id: &str) -> Self {
        Self {
            schema_version: STATE_SCHEMA_VERSION,
            account_id: account_id.to_string(),
            cursor: 0,
            entries: BTreeMap::new(),
        }
    }
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct EncryptedPayload {
    schema_version: u32,
    object_type: SyncObjectType,
    original_id: String,
    value: Value,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SyncedPreferences {
    active_mode_id: String,
}

#[derive(Debug, Clone)]
struct LocalObject {
    object_type: SyncObjectType,
    original_id: String,
    value: Value,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct CloudSyncRunReport {
    pub uploaded: u64,
    pub downloaded: u64,
    pub conflicts_preserved: u64,
    pub next_cursor: u64,
}

fn object_state_key(object_type: SyncObjectType, original_id: &str) -> String {
    format!("{}:{original_id}", object_type.as_str())
}

fn object_uuid(object_type: SyncObjectType, original_id: &str) -> String {
    let digest = Sha256::digest(
        format!(
            "pressay-sync-object-v1:{}:{original_id}",
            object_type.as_str()
        )
        .as_bytes(),
    );
    let mut bytes: [u8; 16] = digest[..16].try_into().expect("SHA-256 prefix is 16 bytes");
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    uuid::Uuid::from_bytes(bytes).to_string()
}

fn change_aad(
    object_type: SyncObjectType,
    object_id: &str,
    revision: u64,
    envelope_version: u8,
) -> Vec<u8> {
    format!(
        "pressay-sync-change:{}:{object_id}:{revision}:{envelope_version}",
        object_type.as_str()
    )
    .into_bytes()
}

fn value_hash(value: &Value) -> Result<String, CloudFailure> {
    let bytes = serde_json::to_vec(value)
        .map_err(|_| CloudFailure::from_code("cloud_sync_payload_invalid"))?;
    Ok(URL_SAFE_NO_PAD.encode(Sha256::digest(bytes)))
}

fn state_path(app: &AppHandle, account_id: &str) -> Result<PathBuf, CloudFailure> {
    let account_id = uuid::Uuid::parse_str(account_id)
        .map_err(|_| CloudFailure::from_code("cloud_account_invalid"))?;
    Ok(crate::portable::app_data_dir(app)
        .map_err(|_| CloudFailure::from_code("cloud_sync_state_unavailable"))?
        .join(format!("cloud-sync-{account_id}.json")))
}

fn read_state(app: &AppHandle, account_id: &str) -> Result<SyncLocalState, CloudFailure> {
    let path = state_path(app, account_id)?;
    let bytes = match std::fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(SyncLocalState::new(account_id));
        }
        Err(_) => return Err(CloudFailure::from_code("cloud_sync_state_unavailable")),
    };
    let state: SyncLocalState = serde_json::from_slice(&bytes)
        .map_err(|_| CloudFailure::from_code("cloud_sync_state_invalid"))?;
    if state.schema_version != STATE_SCHEMA_VERSION || state.account_id != account_id {
        return Err(CloudFailure::from_code("cloud_sync_state_invalid"));
    }
    Ok(state)
}

fn write_state(
    app: &AppHandle,
    account_id: &str,
    state: &SyncLocalState,
) -> Result<(), CloudFailure> {
    let path = state_path(app, account_id)?;
    let parent = path
        .parent()
        .ok_or_else(|| CloudFailure::from_code("cloud_sync_state_unavailable"))?;
    std::fs::create_dir_all(parent)
        .map_err(|_| CloudFailure::from_code("cloud_sync_state_unavailable"))?;
    let temporary = parent.join(format!(".cloud-sync-{}.tmp", uuid::Uuid::new_v4()));
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    options.mode(0o600);
    let mut file = options
        .open(&temporary)
        .map_err(|_| CloudFailure::from_code("cloud_sync_state_unavailable"))?;
    let bytes = serde_json::to_vec(state)
        .map_err(|_| CloudFailure::from_code("cloud_sync_state_invalid"))?;
    if file.write_all(&bytes).is_err() || file.sync_all().is_err() {
        let _ = std::fs::remove_file(&temporary);
        return Err(CloudFailure::from_code("cloud_sync_state_unavailable"));
    }
    std::fs::rename(&temporary, path)
        .map_err(|_| CloudFailure::from_code("cloud_sync_state_unavailable"))
}

fn local_objects(settings: &AppSettings) -> Result<Vec<LocalObject>, CloudFailure> {
    let mut objects = Vec::new();
    for mode in settings
        .pressay_modes
        .iter()
        .filter(|mode| !mode.is_builtin && !is_builtin_mode_id(&mode.id))
    {
        objects.push(LocalObject {
            object_type: SyncObjectType::Mode,
            original_id: mode.id.clone(),
            value: serde_json::to_value(mode)
                .map_err(|_| CloudFailure::from_code("cloud_sync_payload_invalid"))?,
        });
    }
    for profile in &settings.app_profiles {
        objects.push(LocalObject {
            object_type: SyncObjectType::Profile,
            original_id: profile.id.clone(),
            value: serde_json::to_value(profile)
                .map_err(|_| CloudFailure::from_code("cloud_sync_payload_invalid"))?,
        });
    }
    for entry in &settings.dictionary_entries {
        objects.push(LocalObject {
            object_type: SyncObjectType::Dictionary,
            original_id: entry.id.clone(),
            value: serde_json::to_value(entry)
                .map_err(|_| CloudFailure::from_code("cloud_sync_payload_invalid"))?,
        });
    }
    objects.push(LocalObject {
        object_type: SyncObjectType::Preference,
        original_id: "productivity".to_string(),
        value: serde_json::to_value(SyncedPreferences {
            active_mode_id: settings.active_mode_id.clone(),
        })
        .map_err(|_| CloudFailure::from_code("cloud_sync_payload_invalid"))?,
    });
    Ok(objects)
}

fn encrypted_change(
    object: &LocalObject,
    revision: u64,
    tombstone: bool,
    account_key: &[u8; 32],
) -> Result<SyncChangeInput, CloudFailure> {
    let object_id = object_uuid(object.object_type, &object.original_id);
    let payload = EncryptedPayload {
        schema_version: STATE_SCHEMA_VERSION,
        object_type: object.object_type,
        original_id: object.original_id.clone(),
        value: if tombstone {
            Value::Null
        } else {
            object.value.clone()
        },
    };
    let plaintext = serde_json::to_vec(&payload)
        .map_err(|_| CloudFailure::from_code("cloud_sync_payload_invalid"))?;
    let envelope = crate::sync_crypto::encrypt_change(
        account_key,
        &plaintext,
        &change_aad(object.object_type, &object_id, revision, ENVELOPE_VERSION),
    )
    .map_err(|_| CloudFailure::from_code("cloud_sync_encryption_failed"))?;
    if envelope.len() > MAX_ENVELOPE_BYTES {
        return Err(CloudFailure::from_code("cloud_sync_payload_too_large"));
    }
    Ok(SyncChangeInput {
        object_type: object.object_type,
        object_id,
        revision,
        envelope: STANDARD.encode(envelope),
        envelope_version: ENVELOPE_VERSION,
        tombstone,
    })
}

fn pending_local_changes(
    settings: &AppSettings,
    state: &SyncLocalState,
    account_key: &[u8; 32],
) -> Result<(Vec<SyncChangeInput>, BTreeMap<String, SyncEntryState>), CloudFailure> {
    let objects = local_objects(settings)?;
    let present = objects
        .iter()
        .map(|object| object_state_key(object.object_type, &object.original_id))
        .collect::<HashSet<_>>();
    let mut next_entries = state.entries.clone();
    let mut changes = Vec::new();
    for object in &objects {
        let key = object_state_key(object.object_type, &object.original_id);
        let hash = value_hash(&object.value)?;
        let previous = state.entries.get(&key).cloned().unwrap_or_default();
        if previous.hash != hash || previous.tombstone {
            let revision = previous.revision.saturating_add(1).max(1);
            changes.push(encrypted_change(object, revision, false, account_key)?);
            next_entries.insert(
                key,
                SyncEntryState {
                    revision,
                    hash,
                    tombstone: false,
                },
            );
        }
    }
    for (key, previous) in &state.entries {
        if present.contains(key) || previous.tombstone {
            continue;
        }
        let Some((kind, original_id)) = key.split_once(':') else {
            return Err(CloudFailure::from_code("cloud_sync_state_invalid"));
        };
        let object_type = parse_object_type(kind)?;
        let object = LocalObject {
            object_type,
            original_id: original_id.to_string(),
            value: Value::Null,
        };
        let revision = previous.revision.saturating_add(1).max(1);
        changes.push(encrypted_change(&object, revision, true, account_key)?);
        next_entries.insert(
            key.clone(),
            SyncEntryState {
                revision,
                hash: value_hash(&Value::Null)?,
                tombstone: true,
            },
        );
    }
    Ok((changes, next_entries))
}

fn parse_object_type(value: &str) -> Result<SyncObjectType, CloudFailure> {
    match value {
        "mode" => Ok(SyncObjectType::Mode),
        "profile" => Ok(SyncObjectType::Profile),
        "dictionary" => Ok(SyncObjectType::Dictionary),
        "preference" => Ok(SyncObjectType::Preference),
        _ => Err(CloudFailure::from_code("cloud_sync_payload_invalid")),
    }
}

fn decrypt_payload(
    change: &SyncChangeOutput,
    account_key: &[u8; 32],
) -> Result<EncryptedPayload, CloudFailure> {
    if change.envelope_version != ENVELOPE_VERSION || change.envelope.len() > 1_500_000 {
        return Err(CloudFailure::from_code("cloud_sync_envelope_invalid"));
    }
    let envelope = STANDARD
        .decode(&change.envelope)
        .map_err(|_| CloudFailure::from_code("cloud_sync_envelope_invalid"))?;
    let plaintext = crate::sync_crypto::decrypt_change(
        account_key,
        &envelope,
        &change_aad(
            change.object_type,
            &change.object_id,
            change.revision,
            change.envelope_version,
        ),
    )
    .map_err(|_| CloudFailure::from_code("cloud_sync_envelope_invalid"))?;
    let payload: EncryptedPayload = serde_json::from_slice(&plaintext)
        .map_err(|_| CloudFailure::from_code("cloud_sync_payload_invalid"))?;
    if payload.schema_version != STATE_SCHEMA_VERSION
        || payload.object_type != change.object_type
        || object_uuid(payload.object_type, &payload.original_id) != change.object_id
        || change.tombstone != payload.value.is_null()
    {
        return Err(CloudFailure::from_code("cloud_sync_payload_invalid"));
    }
    Ok(payload)
}

fn conflict_id(original_id: &str, source_device_id: &str, revision: u64) -> String {
    let suffix = format!(
        "-sync-{}-{revision}",
        &source_device_id[..8.min(source_device_id.len())]
    );
    let maximum = 64_usize.saturating_sub(suffix.len());
    format!(
        "{}{suffix}",
        original_id.chars().take(maximum).collect::<String>()
    )
}

fn remove_object(settings: &mut AppSettings, object_type: SyncObjectType, id: &str) {
    match object_type {
        SyncObjectType::Mode => settings
            .pressay_modes
            .retain(|mode| mode.id != id || mode.is_builtin || is_builtin_mode_id(&mode.id)),
        SyncObjectType::Profile => settings.app_profiles.retain(|profile| profile.id != id),
        SyncObjectType::Dictionary => settings.dictionary_entries.retain(|entry| entry.id != id),
        SyncObjectType::Preference => {}
    }
}

fn apply_payload(
    settings: &mut AppSettings,
    state: &mut SyncLocalState,
    change: &SyncChangeOutput,
    payload: EncryptedPayload,
) -> Result<bool, CloudFailure> {
    let key = object_state_key(change.object_type, &payload.original_id);
    let previous = state.entries.get(&key).cloned().unwrap_or_default();
    if change.revision < previous.revision {
        return Ok(false);
    }
    let local = local_objects(settings)?.into_iter().find(|object| {
        object.object_type == change.object_type && object.original_id == payload.original_id
    });
    let local_hash = local
        .as_ref()
        .map(|object| value_hash(&object.value))
        .transpose()?;
    let locally_unchanged = local_hash.as_deref() == Some(previous.hash.as_str())
        || (local.is_none() && previous.tombstone);

    if change.tombstone {
        if !change.conflict && (locally_unchanged || previous.revision == 0) {
            remove_object(settings, change.object_type, &payload.original_id);
            state.entries.insert(
                key,
                SyncEntryState {
                    revision: change.revision,
                    hash: value_hash(&Value::Null)?,
                    tombstone: true,
                },
            );
            return Ok(false);
        }
        state.entries.insert(
            key,
            SyncEntryState {
                revision: change.revision.max(previous.revision),
                hash: value_hash(&Value::Null)?,
                tombstone: false,
            },
        );
        return Ok(true);
    }

    let remote_hash = value_hash(&payload.value)?;
    if local_hash.as_deref() == Some(remote_hash.as_str()) {
        state.entries.insert(
            key,
            SyncEntryState {
                revision: change.revision.max(previous.revision),
                hash: remote_hash,
                tombstone: false,
            },
        );
        return Ok(false);
    }
    let preserve_conflict = change.conflict || (!locally_unchanged && local.is_some());
    match change.object_type {
        SyncObjectType::Mode => {
            let mut mode: PressayMode = serde_json::from_value(payload.value)
                .map_err(|_| CloudFailure::from_code("cloud_sync_payload_invalid"))?;
            validate_mode(&mode)
                .map_err(|_| CloudFailure::from_code("cloud_sync_payload_invalid"))?;
            if preserve_conflict {
                mode.id = conflict_id(&mode.id, &change.source_device_id, change.revision);
                mode.is_builtin = false;
                validate_mode(&mode)
                    .map_err(|_| CloudFailure::from_code("cloud_sync_payload_invalid"))?;
                remove_object(settings, SyncObjectType::Mode, &mode.id);
                settings.pressay_modes.push(mode);
            } else {
                remove_object(settings, SyncObjectType::Mode, &mode.id);
                settings.pressay_modes.push(mode);
            }
        }
        SyncObjectType::Profile => {
            let mut profile: AppProfile = serde_json::from_value(payload.value)
                .map_err(|_| CloudFailure::from_code("cloud_sync_payload_invalid"))?;
            let mode_ids = settings
                .pressay_modes
                .iter()
                .map(|mode| mode.id.as_str())
                .collect::<HashSet<_>>();
            validate_profile(&profile, &mode_ids)
                .map_err(|_| CloudFailure::from_code("cloud_sync_payload_invalid"))?;
            if preserve_conflict {
                profile.id = conflict_id(&profile.id, &change.source_device_id, change.revision);
                profile.priority = -10_000;
                remove_object(settings, SyncObjectType::Profile, &profile.id);
                settings.app_profiles.push(profile);
            } else {
                remove_object(settings, SyncObjectType::Profile, &profile.id);
                settings.app_profiles.push(profile);
            }
        }
        SyncObjectType::Dictionary => {
            let mut entry: DictionaryEntry = serde_json::from_value(payload.value)
                .map_err(|_| CloudFailure::from_code("cloud_sync_payload_invalid"))?;
            validate_dictionary(std::slice::from_ref(&entry))
                .map_err(|_| CloudFailure::from_code("cloud_sync_payload_invalid"))?;
            if preserve_conflict {
                entry.id = conflict_id(&entry.id, &change.source_device_id, change.revision);
                entry.enabled = false;
                remove_object(settings, SyncObjectType::Dictionary, &entry.id);
                settings.dictionary_entries.push(entry);
            } else {
                remove_object(settings, SyncObjectType::Dictionary, &entry.id);
                settings.dictionary_entries.push(entry);
            }
        }
        SyncObjectType::Preference => {
            let preferences: SyncedPreferences = serde_json::from_value(payload.value)
                .map_err(|_| CloudFailure::from_code("cloud_sync_payload_invalid"))?;
            if !preserve_conflict
                && settings
                    .pressay_modes
                    .iter()
                    .any(|mode| mode.id == preferences.active_mode_id)
            {
                settings.active_mode_id = preferences.active_mode_id;
            }
        }
    }
    state.entries.insert(
        key,
        SyncEntryState {
            revision: change.revision.max(previous.revision),
            hash: if preserve_conflict {
                remote_hash
            } else {
                local_objects(settings)?
                    .into_iter()
                    .find(|object| {
                        object.object_type == change.object_type
                            && object.original_id == payload.original_id
                    })
                    .map(|object| value_hash(&object.value))
                    .transpose()?
                    .unwrap_or(remote_hash)
            },
            tombstone: false,
        },
    );
    Ok(preserve_conflict)
}

async fn pull_changes(
    app: &AppHandle,
    settings: &mut AppSettings,
    state: &mut SyncLocalState,
    account_key: &[u8; 32],
    device_id: &str,
) -> Result<(u64, u64), CloudFailure> {
    let mut downloaded = 0_u64;
    let mut conflicts = 0_u64;
    loop {
        let page = cloud::fetch_sync_changes(settings, device_id, state.cursor).await?;
        for change in &page.changes {
            if uuid::Uuid::parse_str(&change.source_device_id).is_err()
                || uuid::Uuid::parse_str(&change.object_id).is_err()
            {
                return Err(CloudFailure::from_code("cloud_response_invalid"));
            }
            if change.source_device_id != device_id {
                let payload = decrypt_payload(change, account_key)?;
                if apply_payload(settings, state, change, payload)? {
                    conflicts = conflicts.saturating_add(1);
                }
                downloaded = downloaded.saturating_add(1);
            }
            state.cursor = state.cursor.max(change.sequence_id);
        }
        state.cursor = state.cursor.max(page.next_cursor);
        if !page.has_more {
            break;
        }
    }
    write_settings(app, settings.clone());
    Ok((downloaded, conflicts))
}

pub async fn run_cloud_sync(app: &AppHandle) -> Result<CloudSyncRunReport, CloudFailure> {
    let mut settings = get_settings(app);
    let account_id = settings
        .pressay_cloud_account_id
        .clone()
        .ok_or_else(|| CloudFailure::from_code("cloud_not_connected"))?;
    let device_id = settings
        .pressay_cloud_device_id
        .clone()
        .ok_or_else(|| CloudFailure::from_code("cloud_not_connected"))?;
    let private = get_cloud_sync_device_key(&account_id)
        .map_err(|_| CloudFailure::from_code("cloud_keychain_unavailable"))?
        .ok_or_else(|| CloudFailure::from_code("cloud_sync_not_configured"))?;
    let account_key = get_cloud_sync_account_key(&account_id)
        .map_err(|_| CloudFailure::from_code("cloud_keychain_unavailable"))?
        .ok_or_else(|| CloudFailure::from_code("cloud_sync_not_ready"))?;
    let _ = private;
    let mut state = read_state(app, &account_id)?;
    let (mut downloaded, mut conflicts) =
        pull_changes(app, &mut settings, &mut state, &account_key, &device_id).await?;
    write_state(app, &account_id, &state)?;

    let (changes, next_entries) = pending_local_changes(&settings, &state, &account_key)?;
    let mut uploaded = 0_u64;
    for batch in changes.chunks(100) {
        let (accepted, server_conflicts, _) =
            cloud::append_sync_changes(&settings, &device_id, batch).await?;
        uploaded = uploaded.saturating_add(accepted);
        conflicts = conflicts.saturating_add(server_conflicts);
    }
    if !changes.is_empty() {
        state.entries = next_entries;
        write_state(app, &account_id, &state)?;
        let (new_downloaded, new_conflicts) =
            pull_changes(app, &mut settings, &mut state, &account_key, &device_id).await?;
        downloaded = downloaded.saturating_add(new_downloaded);
        conflicts = conflicts.saturating_add(new_conflicts);
    }
    write_state(app, &account_id, &state)?;
    Ok(CloudSyncRunReport {
        uploaded,
        downloaded,
        conflicts_preserved: conflicts,
        next_cursor: state.cursor,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deterministic_ids_do_not_reveal_original_ids() {
        let first = object_uuid(SyncObjectType::Mode, "my-private-mode");
        assert_eq!(first, object_uuid(SyncObjectType::Mode, "my-private-mode"));
        assert_ne!(
            first,
            object_uuid(SyncObjectType::Profile, "my-private-mode")
        );
        assert!(!first.contains("private"));
        assert!(uuid::Uuid::parse_str(&first).is_ok());
    }

    #[test]
    fn aad_binds_type_id_revision_and_version() {
        let base = change_aad(SyncObjectType::Mode, "id", 1, 1);
        assert_ne!(base, change_aad(SyncObjectType::Profile, "id", 1, 1));
        assert_ne!(base, change_aad(SyncObjectType::Mode, "other", 1, 1));
        assert_ne!(base, change_aad(SyncObjectType::Mode, "id", 2, 1));
        assert_ne!(base, change_aad(SyncObjectType::Mode, "id", 1, 2));
    }

    #[test]
    fn conflict_ids_are_bounded_and_traceable() {
        let id = conflict_id(&"a".repeat(80), "12345678-0000-0000-0000-000000000000", 42);
        assert!(id.len() <= 64);
        assert!(id.ends_with("-sync-12345678-42"));
    }
}
