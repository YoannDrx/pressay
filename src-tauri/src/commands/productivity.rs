use crate::productivity::{
    is_builtin_mode_id, validate_dictionary, validate_mode, validate_profile, AppProfile,
    DictionaryEntry, PressayMode, ProductivityConfig, PRODUCTIVITY_SCHEMA_VERSION,
};
use crate::settings::{get_settings, write_settings};
use std::cmp::Reverse;
use std::collections::HashSet;
use tauri::AppHandle;

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
    let mut settings = get_settings(&app);
    let mode_ids = settings
        .pressay_modes
        .iter()
        .map(|mode| mode.id.as_str())
        .collect::<HashSet<_>>();
    validate_profile(&profile, &mode_ids)?;
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
