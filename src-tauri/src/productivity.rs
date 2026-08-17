use regex::Regex;
use serde::{Deserialize, Serialize};
use specta::Type;
use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

pub const PRODUCTIVITY_SCHEMA_VERSION: u32 = 1;
pub const PRODUCTIVITY_EXPORT_SCHEMA_VERSION: u32 = 1;
pub const PRODUCTIVITY_EXPORT_FORMAT: &str = "pressay-productivity";
const MAX_MODE_STEPS: usize = 8;
const MAX_DICTIONARY_ENTRIES: usize = 5_000;
const MAX_PORTABLE_MODES: usize = 1_000;
const MAX_PORTABLE_PROFILES: usize = 1_000;
const BUILTIN_MODE_IDS: [&str; 5] = ["faithful", "clean", "message", "email", "ai_prompt"];
const ALLOWED_VARIABLES: [&str; 4] = ["transcript", "selected", "app_name", "custom_words"];
const CORRECTION_SESSION_TTL_MS: u64 = 2 * 60 * 1_000;

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type, Default)]
#[serde(rename_all = "snake_case")]
pub enum ProcessingRoute {
    #[default]
    Local,
    Byok,
    PressayCloud,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type)]
#[serde(rename_all = "snake_case")]
pub enum ModeStepKind {
    Normalize,
    Dictionary,
    Transform,
    Format,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
pub struct ModeStep {
    pub id: String,
    pub kind: ModeStepKind,
    #[serde(default)]
    pub instruction: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
pub struct PressayMode {
    pub id: String,
    pub name: String,
    pub description: String,
    pub route: ProcessingRoute,
    pub steps: Vec<ModeStep>,
    #[serde(default)]
    pub tone: Option<String>,
    #[serde(default)]
    pub length: Option<String>,
    #[serde(default)]
    pub language: Option<String>,
    #[serde(default)]
    pub is_builtin: bool,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type, Default)]
#[serde(rename_all = "snake_case")]
pub enum DictionaryMatchKind {
    #[default]
    Exact,
    Fuzzy,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
pub struct DictionaryEntry {
    pub id: String,
    pub term: String,
    #[serde(default)]
    pub variants: Vec<String>,
    #[serde(default)]
    pub replacement: Option<String>,
    #[serde(default)]
    pub match_kind: DictionaryMatchKind,
    #[serde(default)]
    pub language: Option<String>,
    #[serde(default = "enabled_by_default")]
    pub enabled: bool,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type, Default)]
#[serde(rename_all = "snake_case")]
pub enum OutputBehavior {
    #[default]
    Paste,
    Copy,
    Type,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
pub struct AppProfile {
    pub id: String,
    pub bundle_id: String,
    pub app_name: String,
    #[serde(default)]
    pub priority: i32,
    pub mode_id: String,
    #[serde(default)]
    pub language: Option<String>,
    #[serde(default)]
    pub microphone: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub output: OutputBehavior,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
pub struct SelectionContext {
    pub selected_text: String,
    pub source_bundle_id: String,
    pub source_app_name: String,
    pub available: bool,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
pub struct CorrectionSession {
    pub text: String,
    pub target_bundle_id: String,
    pub created_at_ms: u64,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
pub struct CorrectionStatus {
    pub available: bool,
    pub armed: bool,
    pub target_app_name: Option<String>,
    pub expires_in_seconds: u64,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
pub struct ProductivityConfig {
    pub schema_version: u32,
    pub active_mode_id: String,
    pub modes: Vec<PressayMode>,
    pub profiles: Vec<AppProfile>,
    pub dictionary: Vec<DictionaryEntry>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ProductivityPortableBundle {
    pub format: String,
    pub schema_version: u32,
    pub exported_at: String,
    pub active_mode_id: String,
    pub modes: Vec<PressayMode>,
    pub profiles: Vec<AppProfile>,
    pub dictionary: Vec<DictionaryEntry>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type, Default)]
pub struct ProductivityTransferReport {
    pub cancelled: bool,
    pub modes_added: u32,
    pub profiles_added: u32,
    pub dictionary_added: u32,
    pub conflicts_preserved: u32,
    pub duplicates_skipped: u32,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
pub struct TargetApplication {
    pub bundle_id: String,
    pub app_name: String,
    pub process_id: i32,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type)]
#[serde(rename_all = "snake_case")]
pub enum ModeSelectionSource {
    Temporary,
    AppProfile,
    Default,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
pub struct ResolvedMode {
    pub mode: PressayMode,
    pub source: ModeSelectionSource,
    pub profile_id: Option<String>,
    pub profile: Option<AppProfile>,
    pub output: OutputBehavior,
    pub target: Option<TargetApplication>,
}

#[derive(Default)]
struct RuntimeInvocation {
    resolved_mode: Option<ResolvedMode>,
    selection: Option<SelectionContext>,
    temporary_mode_id: Option<String>,
    correction: Option<CorrectionRecord>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CorrectionRecord {
    pub session: CorrectionSession,
    pub target: TargetApplication,
}

#[derive(Default)]
struct CorrectionRuntimeState {
    confirmed: Option<CorrectionRecord>,
    pending: HashMap<u64, CorrectionRecord>,
    armed: bool,
}

#[derive(Default)]
pub struct ProductivityRuntime {
    invocation: Mutex<RuntimeInvocation>,
    correction: Mutex<CorrectionRuntimeState>,
}

impl ProductivityRuntime {
    pub fn prepare_invocation(
        &self,
        resolved_mode: Option<ResolvedMode>,
        selection: Option<SelectionContext>,
    ) {
        if let Ok(mut invocation) = self.invocation.lock() {
            invocation.resolved_mode = resolved_mode;
            invocation.selection = selection;
            invocation.correction = None;
        }
    }

    pub(crate) fn prepare_correction_invocation(&self, correction: CorrectionRecord) {
        if let Ok(mut invocation) = self.invocation.lock() {
            invocation.resolved_mode = None;
            invocation.selection = None;
            invocation.correction = Some(correction);
        }
    }

    pub fn set_temporary_mode(&self, mode_id: Option<String>) {
        if let Ok(mut invocation) = self.invocation.lock() {
            invocation.temporary_mode_id = mode_id;
        }
    }

    pub fn take_temporary_mode(&self) -> Option<String> {
        self.invocation
            .lock()
            .ok()
            .and_then(|mut invocation| invocation.temporary_mode_id.take())
    }

    pub fn peek_invocation_mode(&self) -> Option<ResolvedMode> {
        self.invocation
            .lock()
            .ok()
            .and_then(|invocation| invocation.resolved_mode.clone())
    }

    pub(crate) fn take_invocation(
        &self,
    ) -> (
        Option<ResolvedMode>,
        Option<SelectionContext>,
        Option<CorrectionRecord>,
    ) {
        match self.invocation.lock() {
            Ok(mut invocation) => (
                invocation.resolved_mode.take(),
                invocation.selection.take(),
                invocation.correction.take(),
            ),
            Err(_) => (None, None, None),
        }
    }

    pub fn correction_status(&self) -> CorrectionStatus {
        self.correction_status_at(now_ms())
    }

    fn correction_status_at(&self, now: u64) -> CorrectionStatus {
        let Ok(mut state) = self.correction.lock() else {
            return CorrectionStatus {
                available: false,
                armed: false,
                target_app_name: None,
                expires_in_seconds: 0,
            };
        };
        expire_correction(&mut state, now);
        let expires_in_seconds = state
            .confirmed
            .as_ref()
            .map(|record| {
                record
                    .session
                    .created_at_ms
                    .saturating_add(CORRECTION_SESSION_TTL_MS)
                    .saturating_sub(now)
                    .div_ceil(1_000)
            })
            .unwrap_or(0);
        CorrectionStatus {
            available: state.confirmed.is_some(),
            armed: state.armed,
            target_app_name: state
                .confirmed
                .as_ref()
                .map(|record| record.target.app_name.clone()),
            expires_in_seconds,
        }
    }

    pub fn arm_correction(&self) -> Result<CorrectionStatus, String> {
        let now = now_ms();
        let mut state = self
            .correction
            .lock()
            .map_err(|_| "Correction state is unavailable".to_string())?;
        expire_correction(&mut state, now);
        if state.confirmed.is_none() {
            return Err("No recent insertion is available to correct".to_string());
        }
        state.armed = true;
        drop(state);
        Ok(self.correction_status_at(now))
    }

    pub fn cancel_correction(&self) -> CorrectionStatus {
        if let Ok(mut state) = self.correction.lock() {
            state.armed = false;
        }
        self.correction_status()
    }

    pub(crate) fn take_armed_correction(
        &self,
        target: Option<&TargetApplication>,
    ) -> Result<Option<CorrectionRecord>, &'static str> {
        let now = now_ms();
        let mut state = self
            .correction
            .lock()
            .map_err(|_| "correction_state_unavailable")?;
        expire_correction(&mut state, now);
        if !state.armed {
            return Ok(None);
        }
        let Some(record) = state.confirmed.as_ref() else {
            state.armed = false;
            return Err("correction_session_expired");
        };
        let target_matches = target.is_some_and(|target| {
            target.bundle_id == record.target.bundle_id
                && target.process_id == record.target.process_id
        });
        if !target_matches {
            return Err("correction_target_changed");
        }
        state.armed = false;
        Ok(state.confirmed.clone())
    }

    pub(crate) fn stage_correction(
        &self,
        operation_id: u64,
        text: String,
        target: TargetApplication,
    ) {
        if text.trim().is_empty() {
            return;
        }
        if let Ok(mut state) = self.correction.lock() {
            state.confirmed = None;
            state.armed = false;
            state.pending.insert(
                operation_id,
                CorrectionRecord {
                    session: CorrectionSession {
                        text,
                        target_bundle_id: target.bundle_id.clone(),
                        created_at_ms: now_ms(),
                    },
                    target,
                },
            );
        }
    }

    pub(crate) fn confirm_correction(&self, operation_id: u64) {
        if let Ok(mut state) = self.correction.lock() {
            if let Some(mut record) = state.pending.remove(&operation_id) {
                record.session.created_at_ms = now_ms();
                state.confirmed = Some(record);
                state.armed = false;
            }
        }
    }

    pub(crate) fn discard_staged_correction(&self, operation_id: u64) {
        if let Ok(mut state) = self.correction.lock() {
            state.pending.remove(&operation_id);
        }
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn expire_correction(state: &mut CorrectionRuntimeState, now: u64) {
    if state.confirmed.as_ref().is_some_and(|record| {
        now.saturating_sub(record.session.created_at_ms) >= CORRECTION_SESSION_TTL_MS
    }) {
        state.confirmed = None;
        state.armed = false;
    }
}

#[cfg(target_os = "macos")]
pub fn frontmost_application() -> Option<TargetApplication> {
    use objc2_app_kit::NSWorkspace;

    let application = NSWorkspace::sharedWorkspace().frontmostApplication()?;
    let bundle_id = application.bundleIdentifier()?.to_string();
    if bundle_id.trim().is_empty()
        || matches!(
            bundle_id.as_str(),
            "app.pressay.desktop" | "app.pressay.desktop.mas"
        )
    {
        return None;
    }
    let app_name = application
        .localizedName()
        .map(|name| name.to_string())
        .unwrap_or_else(|| bundle_id.clone());
    Some(TargetApplication {
        bundle_id,
        app_name,
        process_id: application.processIdentifier(),
    })
}

#[cfg(not(target_os = "macos"))]
pub fn frontmost_application() -> Option<TargetApplication> {
    None
}

pub fn resolve_mode(
    modes: &[PressayMode],
    profiles: &[AppProfile],
    default_mode_id: &str,
    temporary_mode_id: Option<&str>,
    target: Option<TargetApplication>,
) -> Option<ResolvedMode> {
    let find_mode = |mode_id: &str| modes.iter().find(|mode| mode.id == mode_id).cloned();

    if let Some(mode) = temporary_mode_id.and_then(find_mode) {
        return Some(ResolvedMode {
            mode,
            source: ModeSelectionSource::Temporary,
            profile_id: None,
            profile: None,
            output: OutputBehavior::Paste,
            target,
        });
    }

    if let Some(target_application) = target.as_ref() {
        if let Some((profile, mode)) = profiles
            .iter()
            .filter(|profile| profile.bundle_id == target_application.bundle_id)
            .filter_map(|profile| find_mode(&profile.mode_id).map(|mode| (profile, mode)))
            .max_by_key(|(profile, _)| profile.priority)
        {
            return Some(ResolvedMode {
                mode,
                source: ModeSelectionSource::AppProfile,
                profile_id: Some(profile.id.clone()),
                profile: Some(profile.clone()),
                output: profile.output,
                target,
            });
        }
    }

    find_mode(default_mode_id)
        .or_else(|| find_mode("faithful"))
        .or_else(|| modes.first().cloned())
        .map(|mode| ResolvedMode {
            mode,
            source: ModeSelectionSource::Default,
            profile_id: None,
            profile: None,
            output: OutputBehavior::Paste,
            target,
        })
}

pub struct ModeVariables<'a> {
    pub transcript: &'a str,
    pub selected: Option<&'a str>,
    pub app_name: Option<&'a str>,
    pub custom_words: &'a [String],
}

pub fn render_mode_instruction(instruction: &str, variables: &ModeVariables<'_>) -> String {
    instruction
        .replace("${transcript}", variables.transcript)
        .replace("${selected}", variables.selected.unwrap_or_default())
        .replace("${app_name}", variables.app_name.unwrap_or_default())
        .replace("${custom_words}", &variables.custom_words.join(", "))
}

pub fn mode_uses_variable(mode: &PressayMode, variable: &str) -> bool {
    let token = format!("${{{variable}}}");
    mode.steps.iter().any(|step| {
        step.instruction
            .as_deref()
            .is_some_and(|instruction| instruction.contains(&token))
    })
}

fn enabled_by_default() -> bool {
    true
}

fn step(id: &str, kind: ModeStepKind, instruction: Option<&str>) -> ModeStep {
    ModeStep {
        id: id.to_string(),
        kind,
        instruction: instruction.map(str::to_string),
    }
}

pub fn builtin_modes() -> Vec<PressayMode> {
    vec![
        PressayMode {
            id: "faithful".to_string(),
            name: "Fidèle".to_string(),
            description: "Transcription locale, ponctuation native et dictionnaire.".to_string(),
            route: ProcessingRoute::Local,
            steps: vec![
                step("normalize", ModeStepKind::Normalize, None),
                step("dictionary", ModeStepKind::Dictionary, None),
            ],
            tone: None,
            length: None,
            language: None,
            is_builtin: true,
        },
        PressayMode {
            id: "clean".to_string(),
            name: "Propre".to_string(),
            description: "Retire localement les hésitations, répétitions et artefacts.".to_string(),
            route: ProcessingRoute::Local,
            steps: vec![
                step("normalize", ModeStepKind::Normalize, None),
                step("dictionary", ModeStepKind::Dictionary, None),
                step("clean", ModeStepKind::Format, Some("remove_fillers")),
            ],
            tone: None,
            length: None,
            language: None,
            is_builtin: true,
        },
        remote_mode(
            "message",
            "Message",
            "Reformule en message conversationnel court.",
            "Transforme ${transcript} en message conversationnel concis.",
            "conversationnel",
            "court",
        ),
        remote_mode(
            "email",
            "Email",
            "Structure un email professionnel prêt à envoyer.",
            "Transforme ${transcript} en email professionnel structuré.",
            "professionnel",
            "moyen",
        ),
        remote_mode(
            "ai_prompt",
            "Prompt IA",
            "Transforme la dictée en consigne claire et structurée.",
            "Transforme ${transcript} en consigne structurée. Utilise ${selected} seulement si ce contexte est disponible.",
            "précis",
            "structuré",
        ),
    ]
}

pub fn portable_productivity_bundle(
    active_mode_id: String,
    modes: &[PressayMode],
    profiles: &[AppProfile],
    dictionary: &[DictionaryEntry],
) -> ProductivityPortableBundle {
    ProductivityPortableBundle {
        format: PRODUCTIVITY_EXPORT_FORMAT.to_string(),
        schema_version: PRODUCTIVITY_EXPORT_SCHEMA_VERSION,
        exported_at: chrono::Utc::now().to_rfc3339(),
        active_mode_id,
        modes: modes
            .iter()
            .filter(|mode| !mode.is_builtin && !is_builtin_mode_id(&mode.id))
            .cloned()
            .collect(),
        profiles: profiles.to_vec(),
        dictionary: dictionary.to_vec(),
    }
}

pub fn validate_portable_bundle(bundle: &ProductivityPortableBundle) -> Result<(), String> {
    if bundle.format != PRODUCTIVITY_EXPORT_FORMAT {
        return Err("This file is not a Pressay productivity export".to_string());
    }
    if bundle.schema_version != PRODUCTIVITY_EXPORT_SCHEMA_VERSION {
        return Err(format!(
            "Unsupported productivity export schema {} (expected {})",
            bundle.schema_version, PRODUCTIVITY_EXPORT_SCHEMA_VERSION
        ));
    }
    if bundle.modes.len() > MAX_PORTABLE_MODES {
        return Err(format!(
            "An export cannot contain more than {MAX_PORTABLE_MODES} custom modes"
        ));
    }
    if bundle.profiles.len() > MAX_PORTABLE_PROFILES {
        return Err(format!(
            "An export cannot contain more than {MAX_PORTABLE_PROFILES} application profiles"
        ));
    }
    validate_dictionary(&bundle.dictionary)?;

    let mut mode_ids = builtin_modes()
        .into_iter()
        .map(|mode| mode.id)
        .collect::<HashSet<_>>();
    for mode in &bundle.modes {
        if mode.is_builtin || is_builtin_mode_id(&mode.id) {
            return Err("Exports cannot redefine a built-in Pressay mode".to_string());
        }
        validate_mode(mode)?;
        if !mode_ids.insert(mode.id.clone()) {
            return Err(format!("Duplicate mode id '{}' in export", mode.id));
        }
    }

    let mode_id_refs = mode_ids.iter().map(String::as_str).collect::<HashSet<_>>();
    let mut profile_ids = HashSet::new();
    for profile in &bundle.profiles {
        validate_profile(profile, &mode_id_refs)?;
        if !profile_ids.insert(profile.id.clone()) {
            return Err(format!("Duplicate profile id '{}' in export", profile.id));
        }
    }
    if !mode_ids.contains(&bundle.active_mode_id) {
        return Err("The exported active mode does not exist in the bundle".to_string());
    }
    Ok(())
}

fn unique_import_id(base: &str, existing: &HashSet<String>) -> String {
    for index in 1_u32..=u32::MAX {
        let suffix = format!("-imported-{index}");
        let max_base_len = 64_usize.saturating_sub(suffix.len());
        let trimmed = base.chars().take(max_base_len).collect::<String>();
        let candidate = format!("{trimmed}{suffix}");
        if !existing.contains(&candidate) {
            return candidate;
        }
    }
    unreachable!("u32 import suffix space exhausted")
}

pub fn merge_portable_bundle(
    existing_modes: &mut Vec<PressayMode>,
    existing_profiles: &mut Vec<AppProfile>,
    existing_dictionary: &mut Vec<DictionaryEntry>,
    bundle: ProductivityPortableBundle,
) -> Result<ProductivityTransferReport, String> {
    validate_portable_bundle(&bundle)?;
    let mut report = ProductivityTransferReport::default();
    let mut mode_ids = existing_modes
        .iter()
        .map(|mode| mode.id.clone())
        .collect::<HashSet<_>>();
    let mut mode_remap = HashMap::new();

    for mut imported in bundle.modes {
        if let Some(existing) = existing_modes.iter().find(|mode| mode.id == imported.id) {
            if existing == &imported {
                mode_remap.insert(imported.id.clone(), imported.id.clone());
                report.duplicates_skipped = report.duplicates_skipped.saturating_add(1);
                continue;
            }
            let original_id = imported.id.clone();
            imported.id = unique_import_id(&original_id, &mode_ids);
            mode_remap.insert(original_id, imported.id.clone());
            report.conflicts_preserved = report.conflicts_preserved.saturating_add(1);
        } else {
            mode_remap.insert(imported.id.clone(), imported.id.clone());
        }
        mode_ids.insert(imported.id.clone());
        existing_modes.push(imported);
        report.modes_added = report.modes_added.saturating_add(1);
    }

    let mut profile_ids = existing_profiles
        .iter()
        .map(|profile| profile.id.clone())
        .collect::<HashSet<_>>();
    for mut imported in bundle.profiles {
        if let Some(remapped_mode) = mode_remap.get(&imported.mode_id) {
            imported.mode_id = remapped_mode.clone();
        }
        if existing_profiles.iter().any(|profile| profile == &imported) {
            report.duplicates_skipped = report.duplicates_skipped.saturating_add(1);
            continue;
        }
        let id_conflict = profile_ids.contains(&imported.id);
        let target_conflict = existing_profiles
            .iter()
            .any(|profile| profile.bundle_id == imported.bundle_id);
        if id_conflict {
            imported.id = unique_import_id(&imported.id, &profile_ids);
        }
        if target_conflict {
            // Preserve the imported profile as an inert backup: existing
            // profiles remain earlier at the same minimum priority and win.
            imported.priority = -10_000;
        }
        if id_conflict || target_conflict {
            report.conflicts_preserved = report.conflicts_preserved.saturating_add(1);
        }
        profile_ids.insert(imported.id.clone());
        existing_profiles.push(imported);
        report.profiles_added = report.profiles_added.saturating_add(1);
    }

    let mut dictionary_ids = existing_dictionary
        .iter()
        .map(|entry| entry.id.clone())
        .collect::<HashSet<_>>();
    for mut imported in bundle.dictionary {
        if existing_dictionary.iter().any(|entry| entry == &imported) {
            report.duplicates_skipped = report.duplicates_skipped.saturating_add(1);
            continue;
        }
        let id_conflict = dictionary_ids.contains(&imported.id);
        let semantic_conflict = existing_dictionary.iter().any(|entry| {
            entry.term.to_lowercase() == imported.term.to_lowercase()
                && entry.language == imported.language
                && entry.match_kind == imported.match_kind
        });
        if id_conflict {
            imported.id = unique_import_id(&imported.id, &dictionary_ids);
        }
        if semantic_conflict {
            imported.enabled = false;
        }
        if id_conflict || semantic_conflict {
            report.conflicts_preserved = report.conflicts_preserved.saturating_add(1);
        }
        dictionary_ids.insert(imported.id.clone());
        existing_dictionary.push(imported);
        report.dictionary_added = report.dictionary_added.saturating_add(1);
    }

    let all_mode_ids = existing_modes
        .iter()
        .map(|mode| mode.id.as_str())
        .collect::<HashSet<_>>();
    for mode in existing_modes.iter() {
        validate_mode(mode)?;
    }
    for profile in existing_profiles.iter() {
        validate_profile(profile, &all_mode_ids)?;
    }
    validate_dictionary(existing_dictionary)?;
    Ok(report)
}

fn remote_mode(
    id: &str,
    name: &str,
    description: &str,
    instruction: &str,
    tone: &str,
    length: &str,
) -> PressayMode {
    PressayMode {
        id: id.to_string(),
        name: name.to_string(),
        description: description.to_string(),
        route: ProcessingRoute::Byok,
        steps: vec![
            step("normalize", ModeStepKind::Normalize, None),
            step("dictionary", ModeStepKind::Dictionary, None),
            step("transform", ModeStepKind::Transform, Some(instruction)),
        ],
        tone: Some(tone.to_string()),
        length: Some(length.to_string()),
        language: None,
        is_builtin: true,
    }
}

pub fn validate_mode(mode: &PressayMode) -> Result<(), String> {
    validate_id(&mode.id, "mode")?;
    validate_text(&mode.name, "Mode name", 80)?;
    validate_text(&mode.description, "Mode description", 280)?;
    if mode.steps.is_empty() || mode.steps.len() > MAX_MODE_STEPS {
        return Err(format!(
            "A mode must contain between 1 and {MAX_MODE_STEPS} steps"
        ));
    }

    let mut step_ids = HashSet::new();
    for step in &mode.steps {
        validate_id(&step.id, "step")?;
        if !step_ids.insert(step.id.as_str()) {
            return Err(format!("Duplicate step id '{}'", step.id));
        }
        if let Some(instruction) = &step.instruction {
            validate_text(instruction, "Step instruction", 4_000)?;
            validate_variables(instruction)?;
        }
        match step.kind {
            ModeStepKind::Normalize | ModeStepKind::Dictionary if step.instruction.is_some() => {
                return Err(format!(
                    "Step '{}' does not accept a custom instruction",
                    step.id
                ));
            }
            ModeStepKind::Format if step.instruction.as_deref() != Some("remove_fillers") => {
                return Err(format!(
                    "Step '{}' uses an unsupported local formatter",
                    step.id
                ));
            }
            ModeStepKind::Transform if step.instruction.is_none() => {
                return Err(format!(
                    "Transformation step '{}' requires an instruction",
                    step.id
                ));
            }
            _ => {}
        }
    }

    let has_remote_step = mode
        .steps
        .iter()
        .any(|step| step.kind == ModeStepKind::Transform);
    if mode.route == ProcessingRoute::Local && has_remote_step {
        return Err("A local mode cannot contain a remote transformation step".to_string());
    }
    if mode.route != ProcessingRoute::Local && !has_remote_step {
        return Err("A remote mode must contain an explicit transformation step".to_string());
    }
    Ok(())
}

pub fn validate_dictionary(entries: &[DictionaryEntry]) -> Result<(), String> {
    if entries.len() > MAX_DICTIONARY_ENTRIES {
        return Err(format!(
            "The dictionary cannot exceed {MAX_DICTIONARY_ENTRIES} entries"
        ));
    }
    let mut ids = HashSet::new();
    for entry in entries {
        validate_id(&entry.id, "dictionary entry")?;
        if !ids.insert(entry.id.as_str()) {
            return Err(format!("Duplicate dictionary entry id '{}'", entry.id));
        }
        validate_text(&entry.term, "Dictionary term", 200)?;
        if let Some(replacement) = &entry.replacement {
            validate_text(replacement, "Dictionary replacement", 500)?;
        }
        for variant in &entry.variants {
            validate_text(variant, "Dictionary variant", 200)?;
        }
    }
    Ok(())
}

/// Returns the canonical terms worth supplying to a decoder that supports an
/// initial prompt. Disabled entries are deliberately omitted and explicit
/// replacements win over their source term: the prompt should teach the model
/// the spelling Pressay ultimately wants to emit.
pub fn dictionary_prompt_terms(entries: &[DictionaryEntry]) -> Vec<String> {
    let mut seen = HashSet::new();
    entries
        .iter()
        .filter(|entry| entry.enabled)
        .filter_map(|entry| {
            let value = entry
                .replacement
                .as_deref()
                .filter(|replacement| !replacement.trim().is_empty())
                .unwrap_or(&entry.term)
                .trim();
            let key = value.to_lowercase();
            seen.insert(key).then(|| value.to_string())
        })
        .collect()
}

pub fn dictionary_entries_from_legacy_words(words: &[String]) -> Vec<DictionaryEntry> {
    words
        .iter()
        .enumerate()
        .filter_map(|(index, word)| {
            let term = word.trim();
            (!term.is_empty()).then(|| DictionaryEntry {
                id: format!("legacy_{index}"),
                term: term.to_string(),
                variants: Vec::new(),
                replacement: None,
                match_kind: DictionaryMatchKind::Fuzzy,
                language: None,
                enabled: true,
            })
        })
        .collect()
}

pub fn validate_profile(
    profile: &AppProfile,
    known_mode_ids: &HashSet<&str>,
) -> Result<(), String> {
    validate_id(&profile.id, "profile")?;
    validate_text(&profile.bundle_id, "Bundle ID", 255)?;
    static BUNDLE_ID_PATTERN: OnceLock<Regex> = OnceLock::new();
    let bundle_pattern = BUNDLE_ID_PATTERN
        .get_or_init(|| Regex::new(r"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$").unwrap());
    if !bundle_pattern.is_match(profile.bundle_id.trim()) {
        return Err("Bundle ID must use reverse-DNS notation".to_string());
    }
    validate_text(&profile.app_name, "Application name", 120)?;
    if !(-10_000..=10_000).contains(&profile.priority) {
        return Err("Profile priority must be between -10000 and 10000".to_string());
    }
    if !known_mode_ids.contains(profile.mode_id.as_str()) {
        return Err(format!("Unknown mode id '{}'", profile.mode_id));
    }
    if let Some(language) = profile.language.as_deref() {
        validate_text(language, "Profile language", 35)?;
        static LANGUAGE_PATTERN: OnceLock<Regex> = OnceLock::new();
        let language_pattern = LANGUAGE_PATTERN
            .get_or_init(|| Regex::new(r"^(?:auto|[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*)$").unwrap());
        if !language_pattern.is_match(language) {
            return Err("Profile language must be a valid language tag".to_string());
        }
    }
    if let Some(microphone) = profile.microphone.as_deref() {
        validate_text(microphone, "Profile microphone", 255)?;
    }
    if let Some(model) = profile.model.as_deref() {
        validate_text(model, "Profile model", 500)?;
    }
    Ok(())
}

pub fn is_builtin_mode_id(id: &str) -> bool {
    BUILTIN_MODE_IDS.contains(&id)
}

fn validate_id(value: &str, label: &str) -> Result<(), String> {
    static ID_PATTERN: OnceLock<Regex> = OnceLock::new();
    let pattern = ID_PATTERN.get_or_init(|| Regex::new(r"^[A-Za-z0-9_-]{1,64}$").unwrap());
    if pattern.is_match(value) {
        Ok(())
    } else {
        Err(format!(
            "Invalid {label} id: use 1-64 letters, numbers, hyphens or underscores"
        ))
    }
}

fn validate_text(value: &str, label: &str, max_chars: usize) -> Result<(), String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(format!("{label} cannot be empty"));
    }
    if trimmed.chars().count() > max_chars {
        return Err(format!("{label} cannot exceed {max_chars} characters"));
    }
    Ok(())
}

fn validate_variables(value: &str) -> Result<(), String> {
    static VARIABLE_PATTERN: OnceLock<Regex> = OnceLock::new();
    let pattern = VARIABLE_PATTERN.get_or_init(|| Regex::new(r"\$\{([^}]+)\}").unwrap());
    for captures in pattern.captures_iter(value) {
        let variable = captures.get(1).map(|m| m.as_str()).unwrap_or_default();
        if !ALLOWED_VARIABLES.contains(&variable) {
            return Err(format!("Unknown mode variable '${{{variable}}}'"));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builtin_modes_are_valid_and_ids_are_unique() {
        let modes = builtin_modes();
        let mut ids = HashSet::new();
        for mode in modes {
            validate_mode(&mode).unwrap();
            assert!(mode.is_builtin);
            assert!(ids.insert(mode.id));
        }
    }

    #[test]
    fn decoder_prompt_uses_enabled_canonical_replacements_once() {
        let entries = vec![
            DictionaryEntry {
                id: "one".into(),
                term: "press say".into(),
                variants: vec![],
                replacement: Some("Pressay".into()),
                match_kind: DictionaryMatchKind::Exact,
                language: None,
                enabled: true,
            },
            DictionaryEntry {
                id: "two".into(),
                term: "PRESSAY".into(),
                variants: vec![],
                replacement: None,
                match_kind: DictionaryMatchKind::Fuzzy,
                language: None,
                enabled: true,
            },
            DictionaryEntry {
                id: "disabled".into(),
                term: "Secret".into(),
                variants: vec![],
                replacement: None,
                match_kind: DictionaryMatchKind::Exact,
                language: None,
                enabled: false,
            },
        ];

        assert_eq!(dictionary_prompt_terms(&entries), vec!["Pressay"]);
    }

    #[test]
    fn legacy_words_become_enabled_fuzzy_entries_with_stable_ids() {
        let entries = dictionary_entries_from_legacy_words(&[
            " Handy ".to_string(),
            "".to_string(),
            "ChargeBee".to_string(),
        ]);

        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].id, "legacy_0");
        assert_eq!(entries[0].term, "Handy");
        assert_eq!(entries[1].id, "legacy_2");
        assert_eq!(entries[1].match_kind, DictionaryMatchKind::Fuzzy);
    }

    #[test]
    fn mode_resolution_honours_temporary_profile_then_default_priority() {
        let modes = builtin_modes();
        let profiles = vec![
            AppProfile {
                id: "low".into(),
                bundle_id: "notion.id".into(),
                app_name: "Notion".into(),
                priority: 1,
                mode_id: "clean".into(),
                language: None,
                microphone: None,
                model: None,
                output: OutputBehavior::Copy,
            },
            AppProfile {
                id: "high".into(),
                bundle_id: "notion.id".into(),
                app_name: "Notion".into(),
                priority: 10,
                mode_id: "email".into(),
                language: Some("fr".into()),
                microphone: Some("Studio Mic".into()),
                model: Some("whisper-small".into()),
                output: OutputBehavior::Type,
            },
        ];
        let target = Some(TargetApplication {
            bundle_id: "notion.id".into(),
            app_name: "Notion".into(),
            process_id: 42,
        });

        let temporary = resolve_mode(
            &modes,
            &profiles,
            "faithful",
            Some("message"),
            target.clone(),
        )
        .unwrap();
        assert_eq!(temporary.mode.id, "message");
        assert_eq!(temporary.source, ModeSelectionSource::Temporary);
        assert_eq!(temporary.output, OutputBehavior::Paste);

        let profiled = resolve_mode(&modes, &profiles, "faithful", None, target).unwrap();
        assert_eq!(profiled.mode.id, "email");
        assert_eq!(profiled.profile_id.as_deref(), Some("high"));
        assert_eq!(profiled.output, OutputBehavior::Type);
        let selected_profile = profiled.profile.unwrap();
        assert_eq!(selected_profile.language.as_deref(), Some("fr"));
        assert_eq!(selected_profile.microphone.as_deref(), Some("Studio Mic"));
        assert_eq!(selected_profile.model.as_deref(), Some("whisper-small"));

        let default = resolve_mode(&modes, &profiles, "faithful", None, None).unwrap();
        assert_eq!(default.mode.id, "faithful");
        assert_eq!(default.source, ModeSelectionSource::Default);
    }

    #[test]
    fn invalid_temporary_and_profile_modes_fail_closed_to_default() {
        let modes = builtin_modes();
        let profiles = vec![AppProfile {
            id: "broken".into(),
            bundle_id: "notion.id".into(),
            app_name: "Notion".into(),
            priority: 100,
            mode_id: "missing".into(),
            language: None,
            microphone: None,
            model: None,
            output: OutputBehavior::Copy,
        }];
        let resolved = resolve_mode(
            &modes,
            &profiles,
            "clean",
            Some("missing"),
            Some(TargetApplication {
                bundle_id: "notion.id".into(),
                app_name: "Notion".into(),
                process_id: 42,
            }),
        )
        .unwrap();

        assert_eq!(resolved.mode.id, "clean");
        assert_eq!(resolved.source, ModeSelectionSource::Default);
        assert_eq!(resolved.output, OutputBehavior::Paste);
    }

    #[test]
    fn mode_variables_render_without_leaking_missing_context() {
        let words = vec!["Pressay".to_string(), "Éléonore".to_string()];
        let rendered = render_mode_instruction(
            "${app_name}: ${transcript} / ${selected} / ${custom_words}",
            &ModeVariables {
                transcript: "Hello",
                selected: None,
                app_name: Some("Mail"),
                custom_words: &words,
            },
        );
        assert_eq!(rendered, "Mail: Hello /  / Pressay, Éléonore");
    }

    #[test]
    fn mode_variables_are_allowlisted() {
        let mut mode = remote_mode(
            "custom",
            "Custom",
            "Custom mode",
            "Use ${transcript} and ${app_name}",
            "neutral",
            "short",
        );
        mode.is_builtin = false;
        assert!(validate_mode(&mode).is_ok());

        mode.steps[2].instruction = Some("Leak ${api_key}".to_string());
        assert!(validate_mode(&mode).is_err());
    }

    #[test]
    fn runtime_invocation_is_consumed_once() {
        let runtime = ProductivityRuntime::default();
        let target = TargetApplication {
            bundle_id: "com.apple.mail".into(),
            app_name: "Mail".into(),
            process_id: 42,
        };
        runtime.set_temporary_mode(Some("email".into()));
        assert_eq!(runtime.take_temporary_mode().as_deref(), Some("email"));
        assert_eq!(runtime.take_temporary_mode(), None);

        let resolved = resolve_mode(&builtin_modes(), &[], "faithful", None, Some(target)).unwrap();
        let selection = SelectionContext {
            selected_text: "Context".into(),
            source_bundle_id: "com.apple.mail".into(),
            source_app_name: "Mail".into(),
            available: true,
        };
        runtime.prepare_invocation(Some(resolved.clone()), Some(selection.clone()));

        assert_eq!(
            runtime.take_invocation(),
            (Some(resolved), Some(selection), None)
        );
        assert_eq!(runtime.take_invocation(), (None, None, None));
    }

    #[test]
    fn selection_is_requested_only_by_modes_that_reference_it() {
        let modes = builtin_modes();
        let faithful = modes.iter().find(|mode| mode.id == "faithful").unwrap();
        let prompt = modes.iter().find(|mode| mode.id == "ai_prompt").unwrap();

        assert!(!mode_uses_variable(faithful, "selected"));
        assert!(mode_uses_variable(prompt, "selected"));
        assert!(!mode_uses_variable(prompt, "api_key"));
    }

    #[test]
    fn local_mode_rejects_remote_transformation() {
        let mut mode = builtin_modes().remove(0);
        mode.steps.push(step(
            "remote",
            ModeStepKind::Transform,
            Some("Rewrite ${transcript}"),
        ));
        assert!(validate_mode(&mode).is_err());
    }

    #[test]
    fn mode_rejects_unknown_or_missing_step_configuration() {
        let mut mode = builtin_modes().remove(1);
        mode.steps[2].instruction = Some("unknown_formatter".into());
        assert!(validate_mode(&mode).is_err());

        let mut remote = remote_mode(
            "custom",
            "Custom",
            "Custom mode",
            "Use ${transcript}",
            "neutral",
            "short",
        );
        remote.steps[2].instruction = None;
        assert!(validate_mode(&remote).is_err());
    }

    #[test]
    fn dictionary_rejects_duplicate_ids_and_blank_terms() {
        let entry = DictionaryEntry {
            id: "pressay".to_string(),
            term: "Pressay".to_string(),
            variants: vec!["pressé".to_string()],
            replacement: None,
            match_kind: DictionaryMatchKind::Exact,
            language: Some("fr".to_string()),
            enabled: true,
        };
        assert!(validate_dictionary(std::slice::from_ref(&entry)).is_ok());
        assert!(validate_dictionary(&[entry.clone(), entry]).is_err());
    }

    #[test]
    fn profile_rejects_invalid_language_and_extreme_priority() {
        let mut profile = AppProfile {
            id: "mail".into(),
            bundle_id: "com.apple.mail".into(),
            app_name: "Mail".into(),
            priority: 0,
            mode_id: "faithful".into(),
            language: Some("fr".into()),
            microphone: Some("Studio Mic".into()),
            model: Some("whisper-small".into()),
            output: OutputBehavior::Paste,
        };
        let known_modes = HashSet::from(["faithful"]);
        assert!(validate_profile(&profile, &known_modes).is_ok());

        profile.language = Some("../../secret".into());
        assert!(validate_profile(&profile, &known_modes).is_err());
        profile.language = Some("fr".into());
        profile.priority = 10_001;
        assert!(validate_profile(&profile, &known_modes).is_err());
    }

    #[test]
    fn correction_session_is_confirmed_armed_target_bound_and_consumed() {
        let runtime = ProductivityRuntime::default();
        let target = TargetApplication {
            bundle_id: "com.apple.Notes".into(),
            app_name: "Notes".into(),
            process_id: 42,
        };
        runtime.stage_correction(7, "Original text".into(), target.clone());
        assert!(!runtime.correction_status().available);

        runtime.confirm_correction(7);
        assert!(runtime.correction_status().available);
        assert!(runtime.arm_correction().unwrap().armed);

        let other_target = TargetApplication {
            process_id: 43,
            ..target.clone()
        };
        assert_eq!(
            runtime.take_armed_correction(Some(&other_target)),
            Err("correction_target_changed")
        );
        assert!(runtime.correction_status().armed);

        let correction = runtime
            .take_armed_correction(Some(&target))
            .unwrap()
            .unwrap();
        assert_eq!(correction.session.text, "Original text");
        assert!(!runtime.correction_status().armed);
        assert!(runtime.correction_status().available);
    }

    #[test]
    fn correction_session_expires_after_two_minutes() {
        let runtime = ProductivityRuntime::default();
        let target = TargetApplication {
            bundle_id: "com.apple.Notes".into(),
            app_name: "Notes".into(),
            process_id: 42,
        };
        let record = CorrectionRecord {
            session: CorrectionSession {
                text: "Original text".into(),
                target_bundle_id: target.bundle_id.clone(),
                created_at_ms: 1_000,
            },
            target,
        };
        runtime.correction.lock().unwrap().confirmed = Some(record);

        let status = runtime.correction_status_at(1_000 + CORRECTION_SESSION_TTL_MS);
        assert!(!status.available);
        assert_eq!(status.expires_in_seconds, 0);
    }

    #[test]
    fn portable_export_excludes_builtins_and_rejects_builtin_redefinitions() {
        let mut modes = builtin_modes();
        let mut custom = remote_mode(
            "standup",
            "Stand-up",
            "A concise update",
            "Rewrite ${transcript}",
            "neutral",
            "short",
        );
        custom.is_builtin = false;
        modes.push(custom);
        let bundle = portable_productivity_bundle("standup".into(), &modes, &[], &[]);
        assert_eq!(bundle.modes.len(), 1);
        assert_eq!(bundle.modes[0].id, "standup");
        assert!(validate_portable_bundle(&bundle).is_ok());

        let mut invalid = bundle;
        invalid.modes[0].id = "faithful".into();
        assert!(validate_portable_bundle(&invalid).is_err());
    }

    #[test]
    fn portable_merge_preserves_conflicts_without_overwriting() {
        let mut modes = builtin_modes();
        let mut existing_mode = remote_mode(
            "standup",
            "Existing",
            "Existing mode",
            "Rewrite ${transcript}",
            "neutral",
            "short",
        );
        existing_mode.is_builtin = false;
        modes.push(existing_mode);
        let mut profiles = vec![AppProfile {
            id: "notes".into(),
            bundle_id: "com.apple.Notes".into(),
            app_name: "Notes".into(),
            priority: 10,
            mode_id: "faithful".into(),
            language: None,
            microphone: None,
            model: None,
            output: OutputBehavior::Paste,
        }];
        let mut dictionary = vec![DictionaryEntry {
            id: "pressay".into(),
            term: "press say".into(),
            variants: vec![],
            replacement: Some("Pressay".into()),
            match_kind: DictionaryMatchKind::Exact,
            language: Some("fr".into()),
            enabled: true,
        }];
        let mut imported_mode = remote_mode(
            "standup",
            "Imported",
            "Imported mode",
            "Structure ${transcript}",
            "neutral",
            "short",
        );
        imported_mode.is_builtin = false;
        let bundle = ProductivityPortableBundle {
            format: PRODUCTIVITY_EXPORT_FORMAT.into(),
            schema_version: PRODUCTIVITY_EXPORT_SCHEMA_VERSION,
            exported_at: "2026-08-17T00:00:00Z".into(),
            active_mode_id: "standup".into(),
            modes: vec![imported_mode],
            profiles: vec![AppProfile {
                id: "notes".into(),
                bundle_id: "com.apple.Notes".into(),
                app_name: "Notes imported".into(),
                priority: 50,
                mode_id: "standup".into(),
                language: None,
                microphone: None,
                model: None,
                output: OutputBehavior::Type,
            }],
            dictionary: vec![DictionaryEntry {
                id: "pressay".into(),
                term: "PRESS SAY".into(),
                variants: vec![],
                replacement: Some("Pressay imported".into()),
                match_kind: DictionaryMatchKind::Exact,
                language: Some("fr".into()),
                enabled: true,
            }],
        };

        let report =
            merge_portable_bundle(&mut modes, &mut profiles, &mut dictionary, bundle).unwrap();
        assert_eq!(report.modes_added, 1);
        assert_eq!(report.profiles_added, 1);
        assert_eq!(report.dictionary_added, 1);
        assert_eq!(report.conflicts_preserved, 3);
        assert_eq!(modes.iter().filter(|mode| mode.id == "standup").count(), 1);
        let imported_mode_id = modes
            .iter()
            .find(|mode| mode.name == "Imported")
            .unwrap()
            .id
            .clone();
        assert!(imported_mode_id.starts_with("standup-imported-"));
        let imported_profile = profiles
            .iter()
            .find(|profile| profile.app_name == "Notes imported")
            .unwrap();
        assert_eq!(imported_profile.mode_id, imported_mode_id);
        assert_eq!(imported_profile.priority, -10_000);
        assert!(!dictionary.last().unwrap().enabled);
    }
}
