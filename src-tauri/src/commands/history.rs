use crate::actions::process_transcription_output;
use crate::managers::{
    history::{
        HistoryEntry, HistoryEntryStatus, HistoryManager, HistoryMetadata, PaginatedHistory,
    },
    transcription::TranscriptionManager,
};
use crate::productivity::{ModeSelectionSource, OutputBehavior, ProcessingRoute, ResolvedMode};
use std::sync::Arc;
use tauri::{AppHandle, State};

#[tauri::command]
#[specta::specta]
pub async fn get_history_entries(
    _app: AppHandle,
    history_manager: State<'_, Arc<HistoryManager>>,
    cursor: Option<i64>,
    limit: Option<usize>,
) -> Result<PaginatedHistory, String> {
    history_manager
        .get_history_entries(cursor, limit)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
#[specta::specta]
pub async fn toggle_history_entry_saved(
    _app: AppHandle,
    history_manager: State<'_, Arc<HistoryManager>>,
    id: i64,
) -> Result<(), String> {
    history_manager
        .toggle_saved_status(id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
#[specta::specta]
pub async fn update_history_entry_tags(
    history_manager: State<'_, Arc<HistoryManager>>,
    id: i64,
    tags: Vec<String>,
) -> Result<HistoryEntry, String> {
    history_manager
        .update_tags(id, tags)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
#[specta::specta]
pub async fn reprocess_history_entry(
    app: AppHandle,
    history_manager: State<'_, Arc<HistoryManager>>,
    id: i64,
    mode_id: String,
) -> Result<HistoryEntry, String> {
    let source = history_manager
        .get_entry_by_id(id)
        .await
        .map_err(|error| error.to_string())?
        .ok_or_else(|| format!("History entry {} not found", id))?;
    if source.transcription_text.trim().is_empty() {
        return Err("History entry has no transcription to reprocess".to_string());
    }

    let settings = crate::settings::get_settings(&app);
    let mode = settings
        .pressay_modes
        .iter()
        .find(|mode| mode.id == mode_id)
        .cloned()
        .ok_or_else(|| "Unknown Pressay mode".to_string())?;
    let route = match mode.route {
        ProcessingRoute::Local => "local_stt",
        ProcessingRoute::Byok => "byok",
        ProcessingRoute::PressayCloud => "pressay_cloud",
    };
    let resolved = ResolvedMode {
        mode: mode.clone(),
        source: ModeSelectionSource::Temporary,
        profile_id: None,
        profile: None,
        output: OutputBehavior::Copy,
        target: None,
    };
    let processed = process_transcription_output(
        &app,
        &source.transcription_text,
        false,
        Some(&resolved),
        None,
        None,
    )
    .await
    .map_err(|failure| format!("History transformation failed: {}", failure.code))?;

    history_manager
        .save_entry_with_metadata(
            String::new(),
            source.transcription_text,
            true,
            processed.post_processed_text,
            processed.post_process_prompt,
            false,
            HistoryMetadata {
                tags: source.metadata.tags,
                mode_id: Some(mode.id),
                processing_route: Some(route.to_string()),
                application_name: source.metadata.application_name,
                application_bundle_id: source.metadata.application_bundle_id,
                parent_entry_id: Some(source.id),
                status: HistoryEntryStatus::Completed,
            },
        )
        .map_err(|error| error.to_string())
}

#[tauri::command]
#[specta::specta]
pub async fn toggle_history_audio_saved(
    history_manager: State<'_, Arc<HistoryManager>>,
    id: i64,
) -> Result<crate::managers::history::HistoryEntry, String> {
    history_manager
        .toggle_audio_saved_status(id)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
#[specta::specta]
pub async fn get_history_audio(
    _app: AppHandle,
    history_manager: State<'_, Arc<HistoryManager>>,
    file_name: String,
) -> Result<Vec<u8>, String> {
    history_manager
        .get_audio_bytes(&file_name)
        .map_err(|error| error.to_string())
}

#[tauri::command]
#[specta::specta]
pub async fn delete_history_entry(
    _app: AppHandle,
    history_manager: State<'_, Arc<HistoryManager>>,
    id: i64,
) -> Result<(), String> {
    history_manager
        .delete_entry(id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
#[specta::specta]
pub async fn retry_history_entry_transcription(
    app: AppHandle,
    history_manager: State<'_, Arc<HistoryManager>>,
    transcription_manager: State<'_, Arc<TranscriptionManager>>,
    id: i64,
) -> Result<(), String> {
    let entry = history_manager
        .get_entry_by_id(id)
        .await
        .map_err(|e| e.to_string())?
        .ok_or_else(|| format!("History entry {} not found", id))?;

    if !entry.audio_available {
        return Err("This recording is no longer available".to_string());
    }

    let samples = history_manager
        .get_audio_samples(&entry.file_name)
        .map_err(|e| format!("Failed to load audio: {}", e))?;

    if samples.is_empty() {
        return Err("Recording has no audio samples".to_string());
    }

    transcription_manager.initiate_model_load();

    let tm = Arc::clone(&transcription_manager);
    let transcription = tauri::async_runtime::spawn_blocking(move || tm.transcribe(samples))
        .await
        .map_err(|e| format!("Transcription task panicked: {}", e))?
        .map_err(|e| e.to_string())?;

    if transcription.is_empty() {
        return Err("Recording contains no speech".to_string());
    }

    let processed = process_transcription_output(
        &app,
        &transcription,
        entry.post_process_requested,
        None,
        None,
        None,
    )
    .await
    .map_err(|failure| format!("Transformation failed: {}", failure.code))?;
    history_manager
        .update_transcription(
            id,
            transcription,
            processed.post_processed_text,
            processed.post_process_prompt,
        )
        .map(|_| ())
        .map_err(|e| e.to_string())
}

#[tauri::command]
#[specta::specta]
pub async fn update_history_limit(
    app: AppHandle,
    history_manager: State<'_, Arc<HistoryManager>>,
    limit: usize,
) -> Result<(), String> {
    let mut settings = crate::settings::get_settings(&app);
    settings.history_limit = limit;
    settings.history_enabled = limit > 0;
    crate::settings::write_settings(&app, settings);

    history_manager
        .cleanup_old_entries()
        .map_err(|e| e.to_string())?;

    Ok(())
}

#[tauri::command]
#[specta::specta]
pub async fn update_history_enabled(
    app: AppHandle,
    history_manager: State<'_, Arc<HistoryManager>>,
    enabled: bool,
) -> Result<(), String> {
    let mut settings = crate::settings::get_settings(&app);
    settings.history_enabled = enabled;
    crate::settings::write_settings(&app, settings);
    history_manager
        .cleanup_old_entries()
        .map_err(|error| error.to_string())
}

#[tauri::command]
#[specta::specta]
pub async fn update_history_text_retention(
    app: AppHandle,
    history_manager: State<'_, Arc<HistoryManager>>,
    period: crate::settings::HistoryRetentionPeriod,
) -> Result<(), String> {
    let mut settings = crate::settings::get_settings(&app);
    settings.history_text_retention = period;
    crate::settings::write_settings(&app, settings);
    history_manager
        .cleanup_old_entries()
        .map_err(|error| error.to_string())
}

#[tauri::command]
#[specta::specta]
pub async fn update_history_audio_retention(
    app: AppHandle,
    history_manager: State<'_, Arc<HistoryManager>>,
    period: crate::settings::HistoryRetentionPeriod,
) -> Result<(), String> {
    let mut settings = crate::settings::get_settings(&app);
    settings.history_audio_retention = period;
    crate::settings::write_settings(&app, settings);
    history_manager
        .cleanup_old_entries()
        .map_err(|error| error.to_string())
}

#[tauri::command]
#[specta::specta]
pub async fn delete_all_history(
    history_manager: State<'_, Arc<HistoryManager>>,
) -> Result<(), String> {
    history_manager
        .delete_all_history()
        .map_err(|error| error.to_string())
}

#[tauri::command]
#[specta::specta]
pub async fn update_recording_retention_period(
    app: AppHandle,
    history_manager: State<'_, Arc<HistoryManager>>,
    period: String,
) -> Result<(), String> {
    use crate::settings::RecordingRetentionPeriod;

    let retention_period = match period.as_str() {
        "never" => RecordingRetentionPeriod::Never,
        "preserve_limit" => RecordingRetentionPeriod::PreserveLimit,
        "days3" => RecordingRetentionPeriod::Days3,
        "weeks2" => RecordingRetentionPeriod::Weeks2,
        "months3" => RecordingRetentionPeriod::Months3,
        _ => return Err(format!("Invalid retention period: {}", period)),
    };

    let mut settings = crate::settings::get_settings(&app);
    settings.recording_retention_period = retention_period;
    crate::settings::write_settings(&app, settings);

    history_manager
        .cleanup_old_entries()
        .map_err(|e| e.to_string())?;

    Ok(())
}
