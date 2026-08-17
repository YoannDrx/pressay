//! The bundled, signed Pressay model catalog.
//!
//! `catalog.json` is intentionally small and release-curated. Its detached
//! Ed25519 signature is verified before parsing, and every artifact has a pinned
//! SHA-256 checked again after download. The catalog therefore remains usable
//! offline without trusting the model CDN at runtime.
//!
//! Each entry is normalised into a [`ModelDescriptor`] — the same source-agnostic
//! shape every other producer (HF discovery, on-disk scans, the legacy table)
//! yields — so the catalog is "just another producer". Its explicit `capabilities`
//! map becomes a [`CapabilityProbe`] with confident `Some(..)` values; the runtime
//! `GgufHeaderProber` is the same shape with `None` where a header omits a key,
//! which is why the two are interchangeable (the catalog is a baked probe).

use std::collections::HashMap;

use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use once_cell::sync::Lazy;
use serde::Deserialize;

use crate::managers::model::{
    default_quant_file, EngineType, ModelDescriptor, ModelSource, QuantFile,
};
use crate::managers::model_capabilities::{CapabilityProbe, Compatibility};

#[derive(Deserialize)]
struct CatalogRoot {
    /// Static HTTPS origins tried in order. Objects are addressed as
    /// `{mirror}/{model_id}/{revision}/{filename}`.
    #[serde(default)]
    mirrors: Vec<String>,
    models: Vec<CatalogModel>,
}

/// One model as written in `catalog.json`. Only the fields the descriptor needs
/// are declared; serde ignores the rest (slug, family, license, …).
#[derive(Deserialize)]
struct CatalogModel {
    /// Stable public Pressay model id, e.g. `pressay/whisper-small`.
    id: String,
    /// Immutable artifact revision used in the CDN object path.
    revision: Option<String>,
    name: String,
    description: String,
    architecture: Option<String>,
    languages: Vec<String>,
    capabilities: CatalogCaps,
    license: String,
    speed_score: Option<f32>,
    accuracy_score: Option<f32>,
    files: Vec<QuantFile>,
    default_quant: Option<String>,
    recommended_rank: Option<u32>,
    /// Part of the small curated onboarding set (badged "Recommended"). Distinct
    /// from `recommended_rank`, which only orders the full list.
    #[serde(default)]
    recommended: bool,
}

#[derive(Deserialize)]
struct CatalogCaps {
    streaming: bool,
    translate: bool,
    lang_detect: bool,
    // `timestamps` (a string enum) is present in the catalog but has no
    // `CapabilityProbe` field yet — wire it through when the probe gains one.
}

impl CatalogModel {
    fn to_descriptor(&self, mirror: &str) -> ModelDescriptor {
        let m = self;
        // Fold the selected artifact name into the public id so each immutable
        // model build is independently selectable and cacheable.
        let default_filename = default_quant_file(&m.files, m.default_quant.as_deref())
            .map(|f| f.filename.clone())
            .unwrap_or_default();

        ModelDescriptor {
            id: format!("{}/{}", m.id, default_filename),
            source: ModelSource::Url {
                url: format!(
                    "{}/{}/{}/{}",
                    mirror.trim_end_matches('/'),
                    m.id,
                    m.revision.as_deref().unwrap_or("v1"),
                    default_filename
                ),
                sha256: default_quant_file(&m.files, m.default_quant.as_deref())
                    .and_then(|file| file.sha256.clone()),
            },
            name: m.name.clone(),
            description: m.description.clone(),
            engine_type: EngineType::TranscribeCpp,
            caps: CapabilityProbe {
                verdict: Compatibility::Compatible,
                display_name: None,
                architecture: m.architecture.clone(),
                variant: None,
                languages: Some(m.languages.clone()),
                supports_streaming: Some(m.capabilities.streaming),
                supports_translation: Some(m.capabilities.translate),
                supports_language_detect: Some(m.capabilities.lang_detect),
            },
            files: m.files.clone(),
            default_quant: m.default_quant.clone(),
            // catalog scores are 0–100; ModelInfo / the UI bars use 0.0–1.0.
            speed_score: m.speed_score.unwrap_or(0.0) / 100.0,
            accuracy_score: m.accuracy_score.unwrap_or(0.0) / 100.0,
            recommended_rank: m.recommended_rank,
            recommended: m.recommended,
        }
    }
}

/// The raw parsed catalog. Kept alive (not consumed) so mirror metadata that
/// deliberately stays out of [`ModelDescriptor`] can be looked up separately.
static ROOT: Lazy<CatalogRoot> = Lazy::new(|| {
    verify_catalog_signature().expect("bundled catalog has a valid Pressay signature");
    serde_json::from_slice(include_bytes!("catalog.json"))
        .expect("bundled catalog.json is valid JSON matching the catalog schema")
});

fn verify_catalog_signature() -> Result<(), ed25519_dalek::SignatureError> {
    let public_key = VerifyingKey::from_bytes(include_bytes!("catalog.pub"))?;
    let signature = Signature::from_bytes(include_bytes!("catalog.sig"));
    public_key.verify(include_bytes!("catalog.json"), &signature)
}

/// The bundled catalog, parsed once and normalised into descriptors.
pub static CATALOG: Lazy<Vec<ModelDescriptor>> = Lazy::new(|| {
    let mirror = ROOT
        .mirrors
        .first()
        .expect("signed catalog must declare a primary HTTPS mirror");
    ROOT.models
        .iter()
        .filter(|model| is_commercially_audited_license(&model.license))
        .map(|model| model.to_descriptor(mirror))
        .collect()
});

/// Pressay only exposes models whose redistribution terms have been reviewed
/// for commercial use. Unknown (`other`) and non-commercial licenses fail
/// closed even if a stale catalog generator includes them.
fn is_commercially_audited_license(license: &str) -> bool {
    matches!(license, "mit" | "apache-2.0" | "cc-by-4.0")
}

/// A mirror copy of a catalog model's default file, with the expected content
/// hash for end-to-end verification. Mirrors are untrusted bit-pipes: the
/// sha256 here (from the catalog compiled into the binary) is the trust anchor,
/// which is why it is mandatory — a file without one is never offered from a
/// mirror at all.
pub struct MirrorFile {
    pub url: String,
    pub sha256: String,
    /// Catalog size — drives progress totals and resume sanity checks.
    pub size_bytes: u64,
}

/// Public, immutable copies of the three launch artifacts. These are an
/// availability fallback for fresh installs while Pressay's own CDN remains
/// the preferred source. The URL is not trusted: callers still verify the
/// downloaded bytes against the size and SHA-256 from the signed catalogue.
fn audited_public_fallback(model_id: &str, filename: &str) -> Option<String> {
    let repository = match model_id {
        "pressay/parakeet-v3" => "memoravox/parakeet-tdt-0.6b-v3-gguf",
        "pressay/whisper-small" => "memoravox/whisper-small-gguf",
        "pressay/whisper-large" => "memoravox/whisper-large-v3-gguf",
        _ => return None,
    };

    Some(format!(
        "https://huggingface.co/{repository}/resolve/main/{filename}?download=true"
    ))
}

/// Ordered CDN URLs for a catalog model's file, or empty when the model is not
/// in the signed catalog.
pub fn mirror_fallbacks(model_id: &str) -> Vec<MirrorFile> {
    let Some((m, file)) = ROOT.models.iter().find_map(|m| {
        m.files
            .iter()
            .find(|f| format!("{}/{}", m.id, f.filename) == model_id)
            .map(|f| (m, f))
    }) else {
        return Vec::new();
    };
    let Some(revision) = m.revision.as_deref() else {
        return Vec::new();
    };
    // No hash means no verification means no mirror: never fetch from an
    // untrusted host without the catalog trust anchor.
    let Some(sha256) = file.sha256.as_deref() else {
        return Vec::new();
    };
    let mut mirrors: Vec<MirrorFile> = ROOT
        .mirrors
        .iter()
        .map(|base| MirrorFile {
            url: format!(
                "{}/{}/{}/{}",
                base.trim_end_matches('/'),
                m.id,
                revision,
                file.filename
            ),
            sha256: sha256.to_string(),
            size_bytes: file.size_bytes,
        })
        .collect();

    if let Some(url) = audited_public_fallback(&m.id, &file.filename) {
        mirrors.push(MirrorFile {
            url,
            sha256: sha256.to_string(),
            size_bytes: file.size_bytes,
        });
    }

    mirrors
}

/// The catalog descriptor + specific `files[]` entry owning `filename`,
/// matched across every listed quant. `repo_id` is only used by the optional
/// Hugging Face cache discovery path; Pressay CDN entries never claim those
/// cache files.
pub fn file_in_catalog(
    filename: &str,
    repo_id: Option<&str>,
) -> Option<(&'static ModelDescriptor, &'static QuantFile)> {
    let catalog: &'static Vec<ModelDescriptor> = Lazy::force(&CATALOG);
    catalog.iter().find_map(|d| {
        if let Some(repo) = repo_id {
            match &d.source {
                ModelSource::HuggingFace { repo_id: r, .. } if r == repo => {}
                _ => return None,
            }
        }
        d.files
            .iter()
            .find(|f| f.filename == filename)
            .map(|f| (d, f))
    })
}

/// Editorial recommended rank keyed by descriptor id (the same id the model
/// registry uses). Built once from the catalog.
static RANK_BY_ID: Lazy<HashMap<String, u32>> = Lazy::new(|| {
    CATALOG
        .iter()
        .filter_map(|d| d.recommended_rank.map(|r| (d.id.clone(), r)))
        .collect()
});

/// Recommended rank for a model id (lower = higher priority). Returns
/// `u32::MAX` for unranked/unknown ids so they sort last in an ascending sort.
pub fn rank_of(model_id: &str) -> u32 {
    RANK_BY_ID.get(model_id).copied().unwrap_or(u32::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::managers::model_capabilities::KNOWN_ARCHES;
    use std::collections::BTreeSet;

    #[test]
    fn catalog_parses_and_is_nonempty() {
        assert!(!CATALOG.is_empty(), "bundled catalog should contain models");
    }

    #[test]
    fn catalog_only_contains_commercially_audited_models() {
        assert!(ROOT
            .models
            .iter()
            .all(|model| is_commercially_audited_license(&model.license)));
    }

    #[test]
    fn launch_catalog_is_exactly_the_three_pressay_presets() {
        let ids: BTreeSet<&str> = ROOT.models.iter().map(|model| model.id.as_str()).collect();
        assert_eq!(
            ids,
            BTreeSet::from([
                "pressay/parakeet-v3",
                "pressay/whisper-large",
                "pressay/whisper-small",
            ])
        );
        assert!(ROOT.models.iter().all(|model| model.recommended));
        assert!(CATALOG.iter().all(|model| {
            model.id.starts_with("pressay/") && matches!(model.source, ModelSource::Url { .. })
        }));
    }

    #[test]
    fn catalog_signature_is_valid() {
        verify_catalog_signature().expect("catalog signature must verify");
    }

    #[test]
    fn ids_are_unique() {
        let mut ids: Vec<&str> = CATALOG.iter().map(|d| d.id.as_str()).collect();
        ids.sort_unstable();
        let before = ids.len();
        ids.dedup();
        assert_eq!(before, ids.len(), "catalog descriptor ids must be unique");
    }

    #[test]
    fn scores_are_normalised_0_to_1() {
        for d in CATALOG.iter() {
            assert!((0.0..=1.0).contains(&d.speed_score), "{} speed", d.id);
            assert!((0.0..=1.0).contains(&d.accuracy_score), "{} acc", d.id);
        }
    }

    #[test]
    fn every_catalog_model_has_mirror_fallbacks_with_hashes() {
        // The mirror fallback is the safety net for HF outages and blocked
        // networks; a catalog entry without one (missing revision, missing
        // sha256, empty mirrors) silently loses that net.
        for d in CATALOG.iter() {
            let mirrors = mirror_fallbacks(&d.id);
            assert!(!mirrors.is_empty(), "{}: no mirror fallbacks", d.id);
            for m in &mirrors {
                assert!(
                    m.sha256.len() == 64,
                    "{}: mirror entry lacks a sha256",
                    d.id
                );
                assert!(m.size_bytes > 0, "{}: mirror entry lacks a size", d.id);
                assert!(m.url.starts_with("https://"), "{}: bad url {}", d.id, m.url);
            }
        }
    }

    #[test]
    fn launch_models_have_a_hash_verified_public_fallback() {
        for descriptor in CATALOG.iter() {
            let mirrors = mirror_fallbacks(&descriptor.id);
            let fallback = mirrors
                .last()
                .expect("launch model must have a public fallback");

            assert!(
                fallback
                    .url
                    .starts_with("https://huggingface.co/memoravox/"),
                "{}: unexpected public fallback {}",
                descriptor.id,
                fallback.url
            );
            assert_eq!(fallback.sha256.len(), 64);
            assert!(fallback.size_bytes > 0);
        }
    }

    #[test]
    fn catalog_architectures_are_known_to_capability_probe() {
        let missing: BTreeSet<&str> = CATALOG
            .iter()
            .filter_map(|d| d.caps.architecture.as_deref())
            .filter(|arch| !KNOWN_ARCHES.contains(arch))
            .collect();

        assert!(
            missing.is_empty(),
            "catalog architecture(s) missing from KNOWN_ARCHES: {:?}",
            missing
        );
    }
}
