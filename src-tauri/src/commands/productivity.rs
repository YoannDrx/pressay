use crate::capabilities::{require_capability, ProductCapability};
use crate::productivity::{
    is_builtin_mode_id, merge_portable_bundle, portable_productivity_bundle, validate_dictionary,
    validate_mode, validate_portable_bundle, validate_profile, AppProfile, CorrectionStatus,
    DictionaryEntry, PressayMode, ProductivityConfig, ProductivityPortableBundle,
    ProductivityRuntime, ProductivityTransferReport, PRODUCTIVITY_SCHEMA_VERSION,
};
use crate::settings::{get_settings, write_settings};
use std::cmp::Reverse;
use std::collections::HashSet;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::Path;
use std::sync::Arc;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_dialog::DialogExt;

const MAX_PRODUCTIVITY_IMPORT_BYTES: u64 = 2 * 1024 * 1024;

fn write_private_atomic(path: &Path, contents: &[u8]) -> Result<(), String> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .ok_or_else(|| "The selected export path has no parent directory".to_string())?;
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| "The selected export filename is invalid".to_string())?;
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let temp_path = parent.join(format!(".{file_name}.{}.{}.tmp", std::process::id(), stamp));
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options
        .open(&temp_path)
        .map_err(|error| format!("Could not create the private export file: {error}"))?;
    let write_result = (|| -> std::io::Result<()> {
        file.write_all(contents)?;
        file.sync_all()?;
        Ok(())
    })();
    drop(file);
    if let Err(error) = write_result {
        let _ = fs::remove_file(&temp_path);
        return Err(format!("Could not finish the productivity export: {error}"));
    }
    if let Err(error) = fs::rename(&temp_path, path) {
        let _ = fs::remove_file(&temp_path);
        return Err(format!(
            "Could not replace the productivity export: {error}"
        ));
    }
    #[cfg(unix)]
    if let Ok(directory) = fs::File::open(parent) {
        let _ = directory.sync_all();
    }
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub fn export_productivity_config(app: AppHandle) -> Result<ProductivityTransferReport, String> {
    let suggested_name = format!(
        "pressay-workflows-{}.json",
        chrono::Local::now().format("%Y-%m-%d")
    );
    let Some(selected) = app
        .dialog()
        .file()
        .add_filter("Pressay JSON", &["json"])
        .set_file_name(suggested_name)
        .blocking_save_file()
    else {
        return Ok(ProductivityTransferReport {
            cancelled: true,
            ..Default::default()
        });
    };
    let mut path = selected
        .into_path()
        .map_err(|_| "The selected export path is not a local file".to_string())?;
    if path.extension().is_none() {
        path.set_extension("json");
    }
    let settings = get_settings(&app);
    let bundle = portable_productivity_bundle(
        settings.active_mode_id,
        &settings.pressay_modes,
        &settings.app_profiles,
        &settings.dictionary_entries,
    );
    let contents = serde_json::to_vec_pretty(&bundle)
        .map_err(|error| format!("Could not serialize productivity settings: {error}"))?;
    write_private_atomic(&path, &contents)?;
    Ok(ProductivityTransferReport {
        modes_added: bundle.modes.len() as u32,
        profiles_added: bundle.profiles.len() as u32,
        dictionary_added: bundle.dictionary.len() as u32,
        ..Default::default()
    })
}

#[tauri::command]
#[specta::specta]
pub fn import_productivity_config(app: AppHandle) -> Result<ProductivityTransferReport, String> {
    let Some(selected) = app
        .dialog()
        .file()
        .add_filter("Pressay JSON", &["json"])
        .blocking_pick_file()
    else {
        return Ok(ProductivityTransferReport {
            cancelled: true,
            ..Default::default()
        });
    };
    let path = selected
        .into_path()
        .map_err(|_| "The selected import path is not a local file".to_string())?;
    let metadata = fs::metadata(&path)
        .map_err(|error| format!("Could not inspect the selected import file: {error}"))?;
    if !metadata.is_file() || metadata.len() > MAX_PRODUCTIVITY_IMPORT_BYTES {
        return Err("The import must be a JSON file no larger than 2 MB".to_string());
    }
    let contents = fs::read(&path)
        .map_err(|error| format!("Could not read the selected import file: {error}"))?;
    let bundle: ProductivityPortableBundle = serde_json::from_slice(&contents)
        .map_err(|error| format!("Invalid Pressay productivity JSON: {error}"))?;
    validate_portable_bundle(&bundle)?;

    let model_manager = app.state::<Arc<crate::managers::model::ModelManager>>();
    for profile in &bundle.profiles {
        if let Some(model_id) = profile
            .model
            .as_deref()
            .filter(|model_id| !model_id.trim().is_empty())
        {
            let model = model_manager.get_model_info(model_id).ok_or_else(|| {
                format!(
                    "Profile '{}' references a model outside the audited catalog",
                    profile.id
                )
            })?;
            if !model.is_downloaded {
                return Err(format!(
                    "Download model '{}' before importing profile '{}'",
                    model.name, profile.id
                ));
            }
        }
    }

    let mut settings = get_settings(&app);
    let mut modes = settings.pressay_modes.clone();
    let mut profiles = settings.app_profiles.clone();
    let mut dictionary = settings.dictionary_entries.clone();
    let report = merge_portable_bundle(&mut modes, &mut profiles, &mut dictionary, bundle)?;
    profiles.sort_by_key(|profile| Reverse(profile.priority));
    settings.pressay_modes = modes;
    settings.app_profiles = profiles;
    settings.dictionary_entries = dictionary;
    write_settings(&app, settings);
    Ok(report)
}

pub(crate) fn emit_correction_status(app: &AppHandle) {
    let status = app.state::<ProductivityRuntime>().correction_status();
    let _ = app.emit("correction-status", status);
}

#[tauri::command]
#[specta::specta]
pub fn get_correction_status(app: AppHandle) -> CorrectionStatus {
    app.state::<ProductivityRuntime>().correction_status()
}

#[tauri::command]
#[specta::specta]
pub fn arm_voice_correction(app: AppHandle) -> Result<CorrectionStatus, String> {
    require_capability(&app, ProductCapability::VoiceCorrection)?;
    let settings = get_settings(&app);
    let provider = settings
        .active_post_process_provider()
        .ok_or_else(|| "Configure a text provider before using voice correction".to_string())?;
    let model = settings
        .post_process_models
        .get(&provider.id)
        .map(String::as_str)
        .unwrap_or_default();
    if model.trim().is_empty() {
        return Err("Choose a model for the active text provider first".to_string());
    }

    let status = app.state::<ProductivityRuntime>().arm_correction()?;
    let _ = app.emit("correction-status", status.clone());
    Ok(status)
}

#[tauri::command]
#[specta::specta]
pub fn cancel_voice_correction(app: AppHandle) -> CorrectionStatus {
    let status = app.state::<ProductivityRuntime>().cancel_correction();
    let _ = app.emit("correction-status", status.clone());
    status
}

#[tauri::command]
#[specta::specta]
pub fn get_productivity_config(app: AppHandle) -> ProductivityConfig {
    let settings = get_settings(&app);
    ProductivityConfig {
        schema_version: PRODUCTIVITY_SCHEMA_VERSION,
        active_mode_id: settings.active_mode_id,
        modes: settings.pressay_modes,
        profiles: settings.app_profiles,
        dictionary: settings.dictionary_entries,
    }
}

#[tauri::command]
#[specta::specta]
pub fn upsert_pressay_mode(app: AppHandle, mode: PressayMode) -> Result<(), String> {
    require_capability(&app, ProductCapability::CustomModes)?;
    validate_mode(&mode)?;
    if mode.is_builtin || is_builtin_mode_id(&mode.id) {
        return Err("Built-in modes cannot be overwritten".to_string());
    }
    let mut settings = get_settings(&app);
    if let Some(existing) = settings
        .pressay_modes
        .iter_mut()
        .find(|candidate| candidate.id == mode.id)
    {
        *existing = mode;
    } else {
        settings.pressay_modes.push(mode);
    }
    write_settings(&app, settings);
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub fn delete_pressay_mode(app: AppHandle, mode_id: String) -> Result<(), String> {
    require_capability(&app, ProductCapability::CustomModes)?;
    if is_builtin_mode_id(&mode_id) {
        return Err("Built-in modes cannot be deleted".to_string());
    }
    let mut settings = get_settings(&app);
    let previous_len = settings.pressay_modes.len();
    settings.pressay_modes.retain(|mode| mode.id != mode_id);
    if settings.pressay_modes.len() == previous_len {
        return Err("Mode not found".to_string());
    }
    settings
        .app_profiles
        .retain(|profile| profile.mode_id != mode_id);
    if settings.active_mode_id == mode_id {
        settings.active_mode_id = "faithful".to_string();
    }
    write_settings(&app, settings);
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub fn set_active_pressay_mode(app: AppHandle, mode_id: String) -> Result<(), String> {
    let mut settings = get_settings(&app);
    if !settings.pressay_modes.iter().any(|mode| mode.id == mode_id) {
        return Err("Mode not found".to_string());
    }
    settings.active_mode_id = mode_id;
    write_settings(&app, settings);
    crate::tray::update_tray_menu(&app, None);
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub fn set_temporary_pressay_mode(app: AppHandle, mode_id: Option<String>) -> Result<(), String> {
    if let Some(mode_id) = mode_id.as_deref() {
        let settings = get_settings(&app);
        if !settings.pressay_modes.iter().any(|mode| mode.id == mode_id) {
            return Err("Mode not found".to_string());
        }
    }
    app.state::<crate::productivity::ProductivityRuntime>()
        .set_temporary_mode(mode_id);
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub fn replace_dictionary_entries(
    app: AppHandle,
    entries: Vec<DictionaryEntry>,
) -> Result<(), String> {
    validate_dictionary(&entries)?;
    let mut settings = get_settings(&app);
    settings.dictionary_entries = entries;
    write_settings(&app, settings);
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub fn upsert_app_profile(app: AppHandle, profile: AppProfile) -> Result<(), String> {
    require_capability(&app, ProductCapability::AppProfiles)?;
    let mut settings = get_settings(&app);
    let mode_ids = settings
        .pressay_modes
        .iter()
        .map(|mode| mode.id.as_str())
        .collect::<HashSet<_>>();
    validate_profile(&profile, &mode_ids)?;
    if let Some(model_id) = profile
        .model
        .as_deref()
        .filter(|model_id| !model_id.trim().is_empty())
    {
        let model = app
            .state::<Arc<crate::managers::model::ModelManager>>()
            .get_model_info(model_id)
            .ok_or_else(|| "Profile model was not found in the audited catalog".to_string())?;
        if !model.is_downloaded {
            return Err("Download the profile model before assigning it".to_string());
        }
    }
    if let Some(existing) = settings
        .app_profiles
        .iter_mut()
        .find(|candidate| candidate.id == profile.id)
    {
        *existing = profile;
    } else {
        settings.app_profiles.push(profile);
    }
    settings
        .app_profiles
        .sort_by_key(|profile| Reverse(profile.priority));
    write_settings(&app, settings);
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub fn delete_app_profile(app: AppHandle, profile_id: String) -> Result<(), String> {
    require_capability(&app, ProductCapability::AppProfiles)?;
    let mut settings = get_settings(&app);
    let previous_len = settings.app_profiles.len();
    settings
        .app_profiles
        .retain(|profile| profile.id != profile_id);
    if settings.app_profiles.len() == previous_len {
        return Err("Profile not found".to_string());
    }
    write_settings(&app, settings);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::write_private_atomic;

    #[test]
    fn productivity_export_is_atomic_and_private() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("workflows.json");

        write_private_atomic(&path, br#"{"schema_version":1}"#).unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), br#"{"schema_version":1}"#);

        write_private_atomic(&path, br#"{"schema_version":2}"#).unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), br#"{"schema_version":2}"#);
        assert_eq!(
            std::fs::read_dir(directory.path()).unwrap().count(),
            1,
            "temporary export files must not remain"
        );

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
                0o600
            );
        }
    }
}
