use regex::Regex;
use serde::{Deserialize, Serialize};
use specta::Type;
use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};

pub const PRODUCTIVITY_SCHEMA_VERSION: u32 = 1;
const MAX_MODE_STEPS: usize = 8;
const MAX_DICTIONARY_ENTRIES: usize = 5_000;
const BUILTIN_MODE_IDS: [&str; 5] = ["faithful", "clean", "message", "email", "ai_prompt"];
const ALLOWED_VARIABLES: [&str; 4] = ["transcript", "selected", "app_name", "custom_words"];

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
pub struct ProductivityConfig {
    pub schema_version: u32,
    pub active_mode_id: String,
    pub modes: Vec<PressayMode>,
    pub profiles: Vec<AppProfile>,
    pub dictionary: Vec<DictionaryEntry>,
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
}

#[derive(Default)]
pub struct ProductivityRuntime {
    invocation: Mutex<RuntimeInvocation>,
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

    pub fn take_invocation(&self) -> (Option<ResolvedMode>, Option<SelectionContext>) {
        match self.invocation.lock() {
            Ok(mut invocation) => (invocation.resolved_mode.take(), invocation.selection.take()),
            Err(_) => (None, None),
        }
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

        assert_eq!(runtime.take_invocation(), (Some(resolved), Some(selection)));
        assert_eq!(runtime.take_invocation(), (None, None));
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
}
