use serde::Serialize;
use specta::Type;
use std::sync::Mutex;
use std::time::{Duration, Instant};
use tauri::{AppHandle, Manager};

use crate::cloud::{self, CloudFailure, CloudTranscriptionResponse};
use crate::settings::get_settings;

const FALLBACK_TTL: Duration = Duration::from_secs(2 * 60);
const MAX_FALLBACK_SAMPLES: usize = 1_900_000;

struct PendingCloudTranscription {
    request_id: String,
    created_at: Instant,
    samples: Vec<f32>,
    language: Option<String>,
}

#[derive(Default)]
pub struct CloudTranscriptionRuntime {
    pending: Mutex<Option<PendingCloudTranscription>>,
}

#[derive(Serialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct CloudTranscriptionAvailable {
    pub request_id: String,
    pub duration_seconds: u64,
}

impl CloudTranscriptionRuntime {
    pub fn clear(&self) {
        if let Ok(mut pending) = self.pending.lock() {
            pending.take();
        }
    }

    pub fn offer(
        &self,
        samples: Vec<f32>,
        language: Option<String>,
    ) -> Option<CloudTranscriptionAvailable> {
        if samples.is_empty() || samples.len() > MAX_FALLBACK_SAMPLES {
            self.clear();
            return None;
        }
        let request_id = uuid::Uuid::new_v4().to_string();
        let duration_seconds = (samples.len() as u64).div_ceil(16_000);
        let pending = PendingCloudTranscription {
            request_id: request_id.clone(),
            created_at: Instant::now(),
            samples,
            language: normalize_language(language.as_deref()),
        };
        *self.pending.lock().ok()? = Some(pending);
        Some(CloudTranscriptionAvailable {
            request_id,
            duration_seconds,
        })
    }

    fn take(&self, request_id: &str) -> Result<PendingCloudTranscription, CloudFailure> {
        let mut pending = self
            .pending
            .lock()
            .map_err(|_| CloudFailure::from_code("cloud_transcription_unavailable"))?;
        let candidate = pending
            .take()
            .ok_or_else(|| CloudFailure::from_code("cloud_transcription_expired"))?;
        if candidate.created_at.elapsed() > FALLBACK_TTL || candidate.request_id != request_id {
            return Err(CloudFailure::from_code("cloud_transcription_expired"));
        }
        Ok(candidate)
    }
}

fn normalize_language(language: Option<&str>) -> Option<String> {
    let language = language?.trim();
    if language.eq_ignore_ascii_case("auto") || language.is_empty() {
        return None;
    }
    let base = language.split(['-', '_']).next()?.to_ascii_lowercase();
    (matches!(base.len(), 2 | 3) && base.chars().all(|character| character.is_ascii_lowercase()))
        .then_some(base)
}

pub async fn retry_with_cloud(
    app: &AppHandle,
    request_id: &str,
) -> Result<CloudTranscriptionResponse, CloudFailure> {
    let pending = app.state::<CloudTranscriptionRuntime>().take(request_id)?;
    let settings = get_settings(app);
    let device_id = settings
        .pressay_cloud_device_id
        .as_deref()
        .ok_or_else(|| CloudFailure::from_code("cloud_not_connected"))?;
    let wav = tauri::async_runtime::spawn_blocking(move || {
        crate::audio_toolkit::encode_wav_samples(&pending.samples)
    })
    .await
    .map_err(|_| CloudFailure::from_code("cloud_audio_invalid"))?
    .map_err(|_| CloudFailure::from_code("cloud_audio_invalid"))?;
    cloud::transcribe_audio(
        &settings,
        device_id,
        wav,
        pending.language.as_deref(),
        &format!("desktop-transcription:{request_id}"),
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn language_is_reduced_to_a_backend_safe_base_code() {
        assert_eq!(normalize_language(Some("fr-FR")), Some("fr".to_string()));
        assert_eq!(normalize_language(Some("zh_Hant")), Some("zh".to_string()));
        assert_eq!(normalize_language(Some("auto")), None);
        assert_eq!(normalize_language(Some("invalid language")), None);
    }

    #[test]
    fn pending_audio_is_single_use_and_request_bound() {
        let runtime = CloudTranscriptionRuntime::default();
        let offer = runtime.offer(vec![0.1; 16_000], Some("fr".into())).unwrap();
        assert!(runtime.take("wrong-request").is_err());
        assert!(runtime.take(&offer.request_id).is_err());
    }

    #[test]
    fn oversized_audio_is_not_retained() {
        let runtime = CloudTranscriptionRuntime::default();
        assert!(runtime
            .offer(vec![0.1; MAX_FALLBACK_SAMPLES + 1], None)
            .is_none());
    }
}
