use crate::managers::history::{HistoryEntry, HistoryManager};
use crate::managers::model::ModelManager;
use crate::managers::transcription::TranscriptionManager;
use crate::settings;
use crate::tray_i18n::get_tray_translations;
use log::{debug, error, info, warn};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tauri::image::Image;
use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri::tray::TrayIcon;
use tauri::{AppHandle, Manager, Theme};
use tauri_plugin_clipboard_manager::ClipboardExt;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum TrayIconState {
    Idle,
    Arming,
    Listening,
    Transcribing,
    Transforming,
    Inserting,
    Success,
    Error,
}

impl TrayIconState {
    pub fn from_voice_phase(phase: crate::transcription_coordinator::VoiceSurfacePhase) -> Self {
        use crate::transcription_coordinator::VoiceSurfacePhase;

        match phase {
            VoiceSurfacePhase::Hidden | VoiceSurfacePhase::Cancelled => Self::Idle,
            VoiceSurfacePhase::Arming => Self::Arming,
            VoiceSurfacePhase::Listening => Self::Listening,
            VoiceSurfacePhase::Captured | VoiceSurfacePhase::Transcribing => Self::Transcribing,
            VoiceSurfacePhase::Transforming => Self::Transforming,
            VoiceSurfacePhase::Inserting => Self::Inserting,
            VoiceSurfacePhase::Success => Self::Success,
            VoiceSurfacePhase::Failed => Self::Error,
        }
    }

    fn is_busy(self) -> bool {
        matches!(
            self,
            Self::Arming
                | Self::Listening
                | Self::Transcribing
                | Self::Transforming
                | Self::Inserting
        )
    }
}

const LISTENING_FRAME_INTERVAL: Duration = Duration::from_millis(120);

/// Tauri managed state holding the last icon state set via `change_tray_icon`.
/// The revision prevents an animation frame from overwriting a newer state.
pub struct CurrentTrayIconState {
    state: Mutex<TrayIconState>,
    revision: AtomicU64,
}

impl CurrentTrayIconState {
    pub fn new() -> Self {
        Self {
            state: Mutex::new(TrayIconState::Idle),
            revision: AtomicU64::new(0),
        }
    }

    pub fn get(&self) -> TrayIconState {
        *self.state.lock().unwrap()
    }

    fn set(&self, state: TrayIconState) -> u64 {
        *self.state.lock().unwrap() = state;
        self.revision.fetch_add(1, Ordering::SeqCst) + 1
    }

    fn is_current(&self, state: TrayIconState, revision: u64) -> bool {
        self.get() == state && self.revision.load(Ordering::SeqCst) == revision
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum AppTheme {
    Dark,
    Light,
    Colored, // Pink/colored theme for Linux
}

/// Gets the current app theme, with Linux defaulting to Colored theme
pub fn get_current_theme(app: &AppHandle) -> AppTheme {
    if cfg!(target_os = "linux") {
        // On Linux, always use the colored theme
        AppTheme::Colored
    } else {
        // On Windows the tray icon sits on the taskbar, which follows the
        // *system* theme (SystemUsesLightTheme), not the app theme. With the
        // "Custom" personalization mode the two can differ (e.g. dark taskbar
        // + light apps), and the window theme would pick an icon that is
        // invisible against the taskbar.
        #[cfg(target_os = "windows")]
        if let Some(theme) = windows_taskbar_theme() {
            return theme;
        }

        // On other platforms, map system theme to our app theme
        if let Some(main_window) = app.get_webview_window("main") {
            match main_window.theme().unwrap_or(Theme::Dark) {
                Theme::Light => AppTheme::Light,
                Theme::Dark => AppTheme::Dark,
                _ => AppTheme::Dark, // Default fallback
            }
        } else {
            AppTheme::Dark
        }
    }
}

/// Reads the Windows taskbar theme from the registry.
///
/// Returns None if the value is missing (older Windows 10 builds default to a
/// dark taskbar there, but falling back to the window theme is safer than
/// guessing).
#[cfg(target_os = "windows")]
fn windows_taskbar_theme() -> Option<AppTheme> {
    use winreg::enums::HKEY_CURRENT_USER;
    use winreg::RegKey;

    let personalize = RegKey::predef(HKEY_CURRENT_USER)
        .open_subkey("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize")
        .ok()?;
    let system_uses_light: u32 = personalize.get_value("SystemUsesLightTheme").ok()?;
    Some(if system_uses_light == 1 {
        AppTheme::Light
    } else {
        AppTheme::Dark
    })
}

/// Gets the appropriate icon path for the given theme and state.
///
/// `warning` overlays a badge on the idle icon while keyboard shortcuts are
/// blocked (macOS Secure Input); active states keep their
/// normal icons so in-flight activity stays recognizable.
pub fn get_icon_path(theme: AppTheme, state: TrayIconState, warning: bool) -> &'static str {
    if warning && state == TrayIconState::Idle {
        return match theme {
            AppTheme::Dark => "resources/tray_signal-warning_light.png",
            AppTheme::Light | AppTheme::Colored => "resources/tray_signal-warning.png",
        };
    }
    match theme {
        AppTheme::Dark => match state {
            TrayIconState::Idle => "resources/tray_signal-idle_light.png",
            TrayIconState::Arming => "resources/tray_signal-arming_light.png",
            TrayIconState::Listening => "resources/tray_signal-listening_light.png",
            TrayIconState::Transcribing => "resources/tray_signal-transcribing_light.png",
            TrayIconState::Transforming => "resources/tray_signal-transforming_light.png",
            TrayIconState::Inserting => "resources/tray_signal-inserting_light.png",
            TrayIconState::Success => "resources/tray_signal-success_light.png",
            TrayIconState::Error => "resources/tray_signal-error_light.png",
        },
        AppTheme::Light => match state {
            TrayIconState::Idle => "resources/tray_signal-idle.png",
            TrayIconState::Arming => "resources/tray_signal-arming.png",
            TrayIconState::Listening => "resources/tray_signal-listening.png",
            TrayIconState::Transcribing => "resources/tray_signal-transcribing.png",
            TrayIconState::Transforming => "resources/tray_signal-transforming.png",
            TrayIconState::Inserting => "resources/tray_signal-inserting.png",
            TrayIconState::Success => "resources/tray_signal-success.png",
            TrayIconState::Error => "resources/tray_signal-error.png",
        },
        AppTheme::Colored => match state {
            TrayIconState::Idle => "resources/tray_signal-idle.png",
            TrayIconState::Arming => "resources/tray_signal-arming.png",
            TrayIconState::Listening => "resources/tray_signal-listening.png",
            TrayIconState::Transcribing => "resources/tray_signal-transcribing.png",
            TrayIconState::Transforming => "resources/tray_signal-transforming.png",
            TrayIconState::Inserting => "resources/tray_signal-inserting.png",
            TrayIconState::Success => "resources/tray_signal-success.png",
            TrayIconState::Error => "resources/tray_signal-error.png",
        },
    }
}

fn get_listening_frame_path(theme: AppTheme, frame: usize) -> &'static str {
    const DARK: [&str; 4] = [
        "resources/tray_signal-listening_light.png",
        "resources/tray_signal-listening-1_light.png",
        "resources/tray_signal-listening-2_light.png",
        "resources/tray_signal-listening-3_light.png",
    ];
    const LIGHT: [&str; 4] = [
        "resources/tray_signal-listening.png",
        "resources/tray_signal-listening-1.png",
        "resources/tray_signal-listening-2.png",
        "resources/tray_signal-listening-3.png",
    ];
    match theme {
        AppTheme::Dark => DARK[frame % DARK.len()],
        AppTheme::Light | AppTheme::Colored => LIGHT[frame % LIGHT.len()],
    }
}

fn resolved_tray_image(app: &AppHandle, icon_path: &str) -> tauri::Result<Image<'static>> {
    load_tray_icon(
        app.path()
            .resolve(icon_path, tauri::path::BaseDirectory::Resource),
    )
}

fn start_listening_animation(app: AppHandle, revision: u64) {
    let _ = std::thread::Builder::new()
        .name("pressay-tray-signal".to_string())
        .spawn(move || {
            let mut frame = 1;
            loop {
                std::thread::sleep(LISTENING_FRAME_INTERVAL);
                let state = app.state::<CurrentTrayIconState>();
                if !state.is_current(TrayIconState::Listening, revision) {
                    break;
                }
                let icon_path = get_listening_frame_path(get_current_theme(&app), frame);
                let image = match resolved_tray_image(&app, icon_path) {
                    Ok(image) => image,
                    Err(err) => {
                        error!("Failed to load animated tray icon '{icon_path}': {err}");
                        break;
                    }
                };
                if !state.is_current(TrayIconState::Listening, revision) {
                    break;
                }
                if let Err(err) = app
                    .state::<TrayIcon>()
                    .set_icon_with_as_template(Some(image), true)
                {
                    error!("Failed to animate tray icon '{icon_path}': {err}");
                    break;
                }
                frame = (frame + 1) % 4;
            }
        });
}

pub fn change_tray_icon(app: &AppHandle, icon: TrayIconState) {
    let tray = app.state::<TrayIcon>();
    let theme = get_current_theme(app);

    // Store current state
    let revision = app.state::<CurrentTrayIconState>().set(icon);

    let warning = crate::secure_input::tray_warning_active(app);
    let icon_path = get_icon_path(theme, icon, warning);

    let icon_started = std::time::Instant::now();
    if let Err(err) = resolved_tray_image(app, icon_path)
        .and_then(|image| tray.set_icon_with_as_template(Some(image), true))
    {
        error!("Failed to update tray icon '{icon_path}': {err}");
    }
    let icon_elapsed = icon_started.elapsed();

    if icon == TrayIconState::Listening {
        start_listening_animation(app.clone(), revision);
    }

    // Update menu based on state
    let menu_started = std::time::Instant::now();
    update_tray_menu(app, None);
    debug!(
        "tray icon change ({:?}): icon={} set_icon={:?} menu={:?}",
        icon,
        icon_path,
        icon_elapsed,
        menu_started.elapsed()
    );
}

/// Re-applies the last known tray state — for when only the *theme* changed
/// and the state itself (idle/recording/transcribing) should be preserved.
pub fn refresh_tray_icon(app: &AppHandle) {
    let icon = app.state::<CurrentTrayIconState>().get();
    change_tray_icon(app, icon);
}

fn load_tray_icon(resolved_icon_path: tauri::Result<PathBuf>) -> tauri::Result<Image<'static>> {
    let resolved_icon_path = resolved_icon_path?;
    Image::from_path(&resolved_icon_path).map(Image::to_owned)
}

pub fn tray_tooltip() -> String {
    version_label()
}

fn version_label() -> String {
    if cfg!(debug_assertions) {
        format!("Pressay v{} (Dev)", env!("CARGO_PKG_VERSION"))
    } else {
        format!("Pressay v{}", env!("CARGO_PKG_VERSION"))
    }
}

pub fn update_tray_menu(app: &AppHandle, locale: Option<&str>) {
    let state = app.state::<CurrentTrayIconState>().get();
    let settings = settings::get_settings(app);

    let locale = locale.unwrap_or(&settings.app_language);
    let strings = get_tray_translations(Some(locale.to_string()));

    // Secure Input warning entry (macOS): clicking opens the settings window
    // where the full warning banner explains the situation. Locales that
    // haven't translated the key yet get the English string rather than a
    // blank menu item (build.rs emits "" for missing keys).
    let secure_input_warning = crate::secure_input::tray_warning_active(app).then(|| {
        let label = if strings.secure_input_warning.is_empty() {
            get_tray_translations(Some("en".to_string())).secure_input_warning
        } else {
            strings.secure_input_warning.clone()
        };
        MenuItem::with_id(app, "secure_input_warning", &label, true, None::<&str>)
            .expect("failed to create secure input warning item")
    });

    // Platform-specific accelerators
    #[cfg(target_os = "macos")]
    let (settings_accelerator, quit_accelerator) = (Some("Cmd+,"), Some("Cmd+Q"));
    #[cfg(not(target_os = "macos"))]
    let (settings_accelerator, quit_accelerator) = (Some("Ctrl+,"), Some("Ctrl+Q"));

    // Create common menu items
    let version_label = version_label();
    let version_i = MenuItem::with_id(app, "version", &version_label, false, None::<&str>)
        .expect("failed to create version item");
    let state_i = MenuItem::with_id(
        app,
        "voice_state",
        format!("Signal · {:?}", state),
        false,
        None::<&str>,
    )
    .expect("failed to create voice state item");
    let settings_i = MenuItem::with_id(
        app,
        "settings",
        &strings.settings,
        true,
        settings_accelerator,
    )
    .expect("failed to create settings item");
    let check_updates_i = MenuItem::with_id(
        app,
        "check_updates",
        &strings.check_updates,
        settings.update_checks_enabled,
        None::<&str>,
    )
    .expect("failed to create check updates item");
    let copy_last_transcript_i = MenuItem::with_id(
        app,
        "copy_last_transcript",
        &strings.copy_last_transcript,
        true,
        None::<&str>,
    )
    .expect("failed to create copy last transcript item");
    let model_loaded = app.state::<Arc<TranscriptionManager>>().is_model_loaded();
    let quit_i = MenuItem::with_id(app, "quit", &strings.quit, true, quit_accelerator)
        .expect("failed to create quit item");
    let separator = || PredefinedMenuItem::separator(app).expect("failed to create separator");

    // Build model submenu — label is the active model name
    let model_manager = app.state::<Arc<ModelManager>>();
    let models = model_manager.get_available_models();
    let current_model_id = &settings.selected_model;

    let mut downloaded: Vec<_> = models.into_iter().filter(|m| m.is_downloaded).collect();
    downloaded.sort_by(|a, b| a.name.cmp(&b.name));

    let active_model_name = downloaded
        .iter()
        .find(|m| m.id == *current_model_id)
        .map(|m| m.name.clone())
        .unwrap_or_else(|| strings.model.clone());
    let submenu_label = format!("{} · {}", strings.model, active_model_name);

    let model_submenu = {
        let submenu = Submenu::with_id(app, "model_submenu", &submenu_label, true)
            .expect("failed to create model submenu");

        for model in &downloaded {
            let is_active = model.id == *current_model_id;
            let item_id = format!("model_select:{}", model.id);
            let item =
                CheckMenuItem::with_id(app, &item_id, &model.name, true, is_active, None::<&str>)
                    .expect("failed to create model item");
            let _ = submenu.append(&item);
        }

        submenu
    };

    let unload_model_i = MenuItem::with_id(
        app,
        "unload_model",
        &strings.unload_model,
        model_loaded,
        None::<&str>,
    )
    .expect("failed to create unload model item");

    let active_mode_name = settings
        .pressay_modes
        .iter()
        .find(|mode| mode.id == settings.active_mode_id)
        .map(|mode| mode.name.as_str())
        .unwrap_or("Faithful");
    let mode_submenu = {
        let submenu = Submenu::with_id(
            app,
            "mode_submenu",
            format!("Mode · {active_mode_name}"),
            true,
        )
        .expect("failed to create mode submenu");
        for mode in &settings.pressay_modes {
            let item = CheckMenuItem::with_id(
                app,
                format!("mode_select:{}", mode.id),
                &mode.name,
                true,
                mode.id == settings.active_mode_id,
                None::<&str>,
            )
            .expect("failed to create mode item");
            let _ = submenu.append(&item);
        }
        submenu
    };

    let active_provider = settings
        .post_process_providers
        .iter()
        .find(|provider| provider.id == settings.post_process_provider_id);
    let provider_ready = settings
        .post_process_api_keys_configured
        .get(&settings.post_process_provider_id)
        .copied()
        .unwrap_or(false)
        || settings.post_process_provider_id == "apple_intelligence";
    let provider_label = active_provider
        .map(|provider| provider.label.as_str())
        .unwrap_or("Not configured");
    let route_i = MenuItem::with_id(
        app,
        "processing_route",
        if provider_ready {
            format!("BYOK · {provider_label}")
        } else {
            "BYOK · Not configured".to_string()
        },
        false,
        None::<&str>,
    )
    .expect("failed to create processing route item");

    let account_label = crate::cloud::cached_account_snapshot(&settings)
        .ok()
        .and_then(|snapshot| snapshot.entitlement)
        .map(|entitlement| format!("Pressay Cloud · {:?}", entitlement.tier))
        .unwrap_or_else(|| "Pressay Cloud · Offline".to_string());
    let account_i = MenuItem::with_id(app, "account_state", account_label, false, None::<&str>)
        .expect("failed to create account state item");

    let shortcut_label = settings
        .bindings
        .get("transcribe")
        .map(|binding| binding.current_binding.as_str())
        .unwrap_or("—");
    let shortcut_i = MenuItem::with_id(
        app,
        "shortcut_state",
        format!("Shortcut · {shortcut_label}"),
        false,
        None::<&str>,
    )
    .expect("failed to create shortcut state item");

    let menu = if state.is_busy() {
        let cancel_i = MenuItem::with_id(app, "cancel", &strings.cancel, true, None::<&str>)
            .expect("failed to create cancel item");
        Menu::with_items(
            app,
            &[
                &version_i,
                &state_i,
                &separator(),
                &cancel_i,
                &separator(),
                &mode_submenu,
                &model_submenu,
                &route_i,
                &account_i,
                &shortcut_i,
                &separator(),
                &copy_last_transcript_i,
                &separator(),
                &settings_i,
                &check_updates_i,
                &separator(),
                &quit_i,
            ],
        )
        .expect("failed to create menu")
    } else {
        Menu::with_items(
            app,
            &[
                &version_i,
                &state_i,
                &separator(),
                &copy_last_transcript_i,
                &separator(),
                &mode_submenu,
                &model_submenu,
                &route_i,
                &account_i,
                &shortcut_i,
                &unload_model_i,
                &separator(),
                &settings_i,
                &check_updates_i,
                &separator(),
                &quit_i,
            ],
        )
        .expect("failed to create menu")
    };

    // Both layouts start with [version, state, separator, ...]; slot the warning in
    // right below the version line so it's the first actionable thing seen.
    let mut tooltip = version_label;
    if let Some(warning_item) = secure_input_warning {
        let _ = menu.insert(&warning_item, 3);
        let _ = menu.insert(&separator(), 4);
        tooltip = format!("{} — {}", tooltip, warning_item.text().unwrap_or_default());
    }

    let tray = app.state::<TrayIcon>();
    let _ = tray.set_menu(Some(menu));
    let _ = tray.set_tooltip(Some(tooltip));
}

fn last_transcript_text(entry: &HistoryEntry) -> &str {
    entry
        .post_processed_text
        .as_deref()
        .unwrap_or(&entry.transcription_text)
}

pub fn set_tray_visibility(app: &AppHandle, visible: bool) {
    let tray = app.state::<TrayIcon>();
    if let Err(e) = tray.set_visible(visible) {
        error!("Failed to set tray visibility: {}", e);
    } else {
        info!("Tray visibility set to: {}", visible);
    }
}

pub fn copy_last_transcript(app: &AppHandle) {
    let history_manager = app.state::<Arc<HistoryManager>>();
    let entry = match history_manager.get_latest_completed_entry() {
        Ok(Some(entry)) => entry,
        Ok(None) => {
            warn!("No completed transcription history entries available for tray copy.");
            return;
        }
        Err(err) => {
            error!(
                "Failed to fetch last completed transcription entry: {}",
                err
            );
            return;
        }
    };

    let text = last_transcript_text(&entry);
    if text.trim().is_empty() {
        warn!("Last completed transcription is empty; skipping tray copy.");
        return;
    }

    if let Err(err) = app.clipboard().write_text(text) {
        error!("Failed to copy last transcript to clipboard: {}", err);
        return;
    }

    info!("Copied last transcript to clipboard via tray.");
}

#[cfg(test)]
mod tests {
    use super::{
        get_icon_path, get_listening_frame_path, last_transcript_text, load_tray_icon, AppTheme,
        TrayIconState,
    };
    use crate::managers::history::HistoryEntry;
    use std::collections::HashSet;

    fn build_entry(transcription: &str, post_processed: Option<&str>) -> HistoryEntry {
        HistoryEntry {
            id: 1,
            file_name: "handy-1.wav".to_string(),
            timestamp: 0,
            saved: false,
            title: "Recording".to_string(),
            transcription_text: transcription.to_string(),
            post_processed_text: post_processed.map(|text| text.to_string()),
            post_process_prompt: None,
            post_process_requested: false,
            audio_available: true,
            audio_saved: false,
            metadata: Default::default(),
        }
    }

    #[test]
    fn uses_post_processed_text_when_available() {
        let entry = build_entry("raw", Some("processed"));
        assert_eq!(last_transcript_text(&entry), "processed");
    }

    #[test]
    fn falls_back_to_raw_transcription() {
        let entry = build_entry("raw", None);
        assert_eq!(last_transcript_text(&entry), "raw");
    }

    #[test]
    fn tray_icon_resolution_failure_is_returned_instead_of_panicking() {
        assert!(load_tray_icon(Err(tauri::Error::UnknownPath)).is_err());
    }

    #[test]
    fn tray_icon_returns_err_when_file_does_not_exist() {
        let dir = tempfile::tempdir().expect("failed to create tempdir");
        let missing = dir.path().join("does_not_exist.png");
        assert!(load_tray_icon(Ok(missing)).is_err());
    }

    #[test]
    fn signal_os_has_a_distinct_template_for_every_canonical_state() {
        let states = [
            TrayIconState::Idle,
            TrayIconState::Arming,
            TrayIconState::Listening,
            TrayIconState::Transcribing,
            TrayIconState::Transforming,
            TrayIconState::Inserting,
            TrayIconState::Success,
            TrayIconState::Error,
        ];
        let light_paths: HashSet<_> = states
            .iter()
            .map(|state| get_icon_path(AppTheme::Light, *state, false))
            .collect();
        let dark_paths: HashSet<_> = states
            .iter()
            .map(|state| get_icon_path(AppTheme::Dark, *state, false))
            .collect();

        assert_eq!(light_paths.len(), states.len());
        assert_eq!(dark_paths.len(), states.len());
        assert_eq!(
            get_icon_path(AppTheme::Light, TrayIconState::Idle, true),
            "resources/tray_signal-warning.png"
        );
    }

    #[test]
    fn listening_animation_has_four_distinct_circle_frames_per_theme() {
        for theme in [AppTheme::Light, AppTheme::Dark] {
            let paths: HashSet<_> = (0..4)
                .map(|frame| get_listening_frame_path(theme.clone(), frame))
                .collect();
            assert_eq!(paths.len(), 4);
        }
    }
}
