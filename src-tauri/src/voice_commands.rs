use serde::{Deserialize, Serialize};
use specta::Type;
use std::collections::BTreeMap;

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type)]
#[serde(rename_all = "snake_case")]
pub enum VoiceCommandKind {
    InsertNewLine,
    InsertNewParagraph,
    FormatBulletList,
    InsertSnippet,
    SetTemporaryMode,
    SetNextMode,
    Cancel,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type)]
#[serde(rename_all = "snake_case")]
pub enum VoiceCommandRisk {
    SafeText,
    ContextChange,
}

/// A deliberately small, local command grammar. Commands are only recognized
/// behind an explicit wake phrase so ordinary dictation can never silently turn
/// into an action.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct VoiceCommandIntent {
    pub kind: VoiceCommandKind,
    pub arguments: BTreeMap<String, String>,
    pub risk: VoiceCommandRisk,
    pub preview: String,
    pub confirmation_required: bool,
}

fn strip_wake_phrase(input: &str) -> Option<&str> {
    let trimmed = input.trim();
    const PREFIXES: [&str; 4] = [
        "pressay command",
        "pressay commande",
        "commande pressay",
        "command pressay",
    ];

    PREFIXES.iter().find_map(|prefix| {
        let rest = trimmed.get(prefix.len()..)?;
        trimmed[..prefix.len()]
            .eq_ignore_ascii_case(prefix)
            .then(|| rest.trim_start_matches([' ', ',', ':', '-', '—']).trim())
    })
}

fn intent(kind: VoiceCommandKind, risk: VoiceCommandRisk, preview: &str) -> VoiceCommandIntent {
    VoiceCommandIntent {
        kind,
        arguments: BTreeMap::new(),
        risk,
        preview: preview.to_string(),
        confirmation_required: false,
    }
}

fn argument_intent(
    kind: VoiceCommandKind,
    risk: VoiceCommandRisk,
    argument_name: &str,
    argument: &str,
    preview: String,
) -> Option<VoiceCommandIntent> {
    let argument = argument.trim().trim_end_matches(['.', '!', '?']).trim();
    if argument.is_empty() {
        return None;
    }
    let mut command = intent(kind, risk, &preview);
    command
        .arguments
        .insert(argument_name.to_string(), argument.to_string());
    Some(command)
}

pub fn parse_voice_command(input: &str) -> Option<VoiceCommandIntent> {
    let command = strip_wake_phrase(input)?;
    let normalized = command
        .trim()
        .trim_end_matches(['.', '!', '?'])
        .trim()
        .to_lowercase();

    match normalized.as_str() {
        "new line" | "nouvelle ligne" | "retour à la ligne" => Some(intent(
            VoiceCommandKind::InsertNewLine,
            VoiceCommandRisk::SafeText,
            "Insert a line break",
        )),
        "new paragraph" | "nouveau paragraphe" => Some(intent(
            VoiceCommandKind::InsertNewParagraph,
            VoiceCommandRisk::SafeText,
            "Insert a paragraph break",
        )),
        "next mode" | "mode suivant" => Some(intent(
            VoiceCommandKind::SetNextMode,
            VoiceCommandRisk::ContextChange,
            "Use the next mode for one dictation",
        )),
        "cancel" | "annuler" | "annule" => Some(intent(
            VoiceCommandKind::Cancel,
            VoiceCommandRisk::SafeText,
            "Cancel this dictation",
        )),
        _ => {
            for prefix in ["bullet list:", "liste à puces :", "liste à puces:"] {
                if let Some(payload) = command
                    .get(..prefix.len())
                    .filter(|candidate| candidate.eq_ignore_ascii_case(prefix))
                    .and_then(|_| command.get(prefix.len()..))
                {
                    return argument_intent(
                        VoiceCommandKind::FormatBulletList,
                        VoiceCommandRisk::SafeText,
                        "text",
                        payload,
                        "Format dictated items as a bullet list".to_string(),
                    );
                }
            }
            for prefix in ["snippet ", "extrait "] {
                if let Some(payload) = command
                    .get(..prefix.len())
                    .filter(|candidate| candidate.eq_ignore_ascii_case(prefix))
                    .and_then(|_| command.get(prefix.len()..))
                {
                    return argument_intent(
                        VoiceCommandKind::InsertSnippet,
                        VoiceCommandRisk::SafeText,
                        "name",
                        payload,
                        "Insert a configured local snippet".to_string(),
                    );
                }
            }
            for prefix in ["mode ", "use mode ", "utilise le mode "] {
                if let Some(payload) = command
                    .get(..prefix.len())
                    .filter(|candidate| candidate.eq_ignore_ascii_case(prefix))
                    .and_then(|_| command.get(prefix.len()..))
                {
                    return argument_intent(
                        VoiceCommandKind::SetTemporaryMode,
                        VoiceCommandRisk::ContextChange,
                        "mode",
                        payload,
                        "Use a mode for one dictation".to_string(),
                    );
                }
            }
            None
        }
    }
}

#[tauri::command]
#[specta::specta]
pub fn preview_voice_command(text: String) -> Option<VoiceCommandIntent> {
    parse_voice_command(&text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ordinary_dictation_is_never_a_command() {
        assert!(parse_voice_command("make this a bullet list").is_none());
        assert!(parse_voice_command("please cancel that meeting").is_none());
    }

    #[test]
    fn parses_safe_english_and_french_commands() {
        assert_eq!(
            parse_voice_command("Pressay command, new line").map(|intent| intent.kind),
            Some(VoiceCommandKind::InsertNewLine)
        );
        assert_eq!(
            parse_voice_command("Commande Pressay : mode suivant.").map(|intent| intent.kind),
            Some(VoiceCommandKind::SetNextMode)
        );
    }

    #[test]
    fn command_arguments_are_bounded_by_an_exact_grammar() {
        let intent = parse_voice_command("Pressay command bullet list: alpha; beta; gamma")
            .expect("list command");
        assert_eq!(intent.kind, VoiceCommandKind::FormatBulletList);
        assert_eq!(
            intent.arguments.get("text").map(String::as_str),
            Some("alpha; beta; gamma")
        );
        assert!(!intent.confirmation_required);
    }
}
