//! Silero VAD v6.2 run by transcribe.cpp (GGUF), on the CPU.
//!
//! Replaces the ONNX Runtime build of Silero v4: ONNX Runtime was only needed
//! for this detector and its prebuilt binaries are no longer reliably
//! downloadable, which broke the Windows builds. Ported from upstream Handy
//! (cjpais/Handy #2267, MIT).

use anyhow::Result;
use std::path::Path;
use std::sync::{Mutex, PoisonError};

use transcribe_cpp::{Backend, Model, ModelOptions, VadSession, VadSessionOptions};

use super::{VadFrame, VoiceActivityDetector};
use crate::audio_toolkit::constants;

/// Pressay frames audio in 30 ms (480-sample) chunks; the model scores its
/// own frame size (512 samples). The stream buffers the remainder, so a
/// chunk yields zero or one new probability and the latest one decides.
const PRESSAY_FRAME_SAMPLES: usize = (constants::WHISPER_SAMPLE_RATE * 30 / 1000) as usize;

pub struct SileroVad {
    // `VadSession` is Send but not Sync; the trait requires both. Only ever
    // reached through `get_mut`, so it is never locked and never poisoned.
    session: Mutex<VadSession>,
    threshold: f32,
    last_probability: f32,
}

impl SileroVad {
    pub fn new<P: AsRef<Path>>(model_path: P, threshold: f32) -> Result<Self> {
        if !(0.0..=1.0).contains(&threshold) {
            anyhow::bail!("threshold must be between 0.0 and 1.0");
        }

        let model = Model::load_with(
            model_path.as_ref(),
            &ModelOptions {
                backend: Backend::Cpu,
                device: None,
                ..Default::default()
            },
        )
        .map_err(|e| anyhow::anyhow!("Failed to load VAD model: {e}"))?;

        let info = model
            .vad_info()
            .map_err(|e| anyhow::anyhow!("Model does not support VAD: {e}"))?;
        if info.sample_rate != constants::WHISPER_SAMPLE_RATE as i32 || info.frame_samples <= 0 {
            anyhow::bail!(
                "unsupported VAD model: {} Hz, {} samples per frame",
                info.sample_rate,
                info.frame_samples
            );
        }

        // The session keeps the native model alive on its own.
        let session = model
            .vad_session_with(&VadSessionOptions { n_threads: 1 })
            .map_err(|e| anyhow::anyhow!("Failed to create VAD session: {e}"))?;

        Ok(Self {
            session: Mutex::new(session),
            threshold,
            last_probability: 0.0,
        })
    }
}

impl VoiceActivityDetector for SileroVad {
    fn push_frame<'a>(&'a mut self, frame: &'a [f32]) -> Result<VadFrame<'a>> {
        if frame.len() != PRESSAY_FRAME_SAMPLES {
            anyhow::bail!(
                "expected {PRESSAY_FRAME_SAMPLES} samples, got {}",
                frame.len()
            );
        }

        let result = self
            .session
            .get_mut()
            .unwrap_or_else(PoisonError::into_inner)
            .stream_feed(frame)
            .map_err(|e| anyhow::anyhow!("Silero VAD error: {e}"))?;
        if let Some(probability) = result.probs.last() {
            self.last_probability = *probability;
        }

        if self.last_probability > self.threshold {
            Ok(VadFrame::Speech(frame))
        } else {
            Ok(VadFrame::Noise)
        }
    }

    fn reset(&mut self) {
        // Clear the Silero LSTM state and buffered samples so a new session
        // doesn't inherit recurrent context from the previous recording.
        self.session
            .get_mut()
            .unwrap_or_else(PoisonError::into_inner)
            .stream_reset();
        self.last_probability = 0.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bundled_model() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("resources/models/silero-vad-v6.2-F32.gguf")
    }

    #[test]
    fn silence_is_noise_and_reset_is_safe() {
        crate::managers::transcription::init_transcribe_backend();
        let mut vad = SileroVad::new(bundled_model(), 0.5).unwrap();
        let silence = vec![0.0_f32; PRESSAY_FRAME_SAMPLES];
        for _ in 0..20 {
            assert!(!vad.push_frame(&silence).unwrap().is_speech());
        }
        vad.reset();
        assert!(!vad.push_frame(&silence).unwrap().is_speech());
    }

    #[test]
    fn rejects_frames_of_the_wrong_size() {
        crate::managers::transcription::init_transcribe_backend();
        let mut vad = SileroVad::new(bundled_model(), 0.5).unwrap();
        assert!(vad.push_frame(&[0.0; 512]).is_err());
    }

    /// Speech must be found in a real recording (16 kHz mono 16-bit WAV).
    /// Run with `PRESSAY_VAD_SAMPLE=path.wav cargo test -- --ignored`.
    #[test]
    #[ignore]
    fn detects_speech_in_a_recording() {
        crate::managers::transcription::init_transcribe_backend();
        let path = std::env::var("PRESSAY_VAD_SAMPLE").expect("PRESSAY_VAD_SAMPLE");
        let samples = crate::audio_toolkit::read_wav_samples(&path).unwrap();
        let mut vad = SileroVad::new(bundled_model(), 0.5).unwrap();
        let frames = samples.chunks_exact(PRESSAY_FRAME_SAMPLES).count();
        let speech = samples
            .chunks_exact(PRESSAY_FRAME_SAMPLES)
            .filter(|frame| vad.push_frame(frame).unwrap().is_speech())
            .count();
        eprintln!("speech frames: {speech}/{frames}");
        assert!(speech * 2 > frames, "{speech}/{frames}");
    }
}
