use regex::Regex;
use serde::{Deserialize, Serialize};
use specta::Type;
use std::collections::HashSet;
use std::sync::OnceLock;

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
    if !known_mode_ids.contains(profile.mode_id.as_str()) {
        return Err(format!("Unknown mode id '{}'", profile.mode_id));
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
}
