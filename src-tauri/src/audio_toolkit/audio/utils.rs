use anyhow::Result;
use hound::{WavReader, WavSpec, WavWriter};
use log::debug;
use std::io::Cursor;
use std::path::Path;

/// Peak amplitude at or below which normalized input is treated as silent
/// (-60 dBFS). Peak level keeps the check conservative: any usable excursion
/// above this threshold still reaches the transcription engine.
const SILENT_INPUT_PEAK: f32 = 0.001;

pub fn is_effectively_silent(samples: &[f32]) -> bool {
    samples
        .iter()
        .all(|sample| sample.abs() <= SILENT_INPUT_PEAK)
}

fn wav_spec() -> WavSpec {
    WavSpec {
        channels: 1,
        sample_rate: 16000,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    }
}

fn collect_samples<R: std::io::Read>(reader: WavReader<R>) -> Result<Vec<f32>> {
    let samples = reader
        .into_samples::<i16>()
        .map(|sample| sample.map(|value| value as f32 / i16::MAX as f32))
        .collect::<Result<Vec<f32>, _>>()?;
    Ok(samples)
}

/// Read a WAV file and return normalised f32 samples.
pub fn read_wav_samples<P: AsRef<Path>>(file_path: P) -> Result<Vec<f32>> {
    let reader = WavReader::open(file_path.as_ref())?;
    collect_samples(reader)
}

/// Decode WAV bytes held in memory. Encrypted history audio uses this path so
/// decrypted recordings never need to be materialized as temporary files.
pub fn read_wav_samples_from_bytes(bytes: &[u8]) -> Result<Vec<f32>> {
    collect_samples(WavReader::new(Cursor::new(bytes))?)
}

/// Verify a WAV file by reading it back and checking the sample count.
pub fn verify_wav_file<P: AsRef<Path>>(file_path: P, expected_samples: usize) -> Result<()> {
    let reader = WavReader::open(file_path.as_ref())?;
    let actual_samples = reader.len() as usize;
    if actual_samples != expected_samples {
        anyhow::bail!(
            "WAV sample count mismatch: expected {}, got {}",
            expected_samples,
            actual_samples
        );
    }
    Ok(())
}

/// Save audio samples as a WAV file
pub fn save_wav_file<P: AsRef<Path>>(file_path: P, samples: &[f32]) -> Result<()> {
    let mut writer = WavWriter::create(file_path.as_ref(), wav_spec())?;

    // Convert f32 samples to i16 for WAV
    for sample in samples {
        let sample_i16 = (sample * i16::MAX as f32) as i16;
        writer.write_sample(sample_i16)?;
    }

    writer.finalize()?;
    debug!("Saved WAV file: {:?}", file_path.as_ref());
    Ok(())
}

/// Encode audio samples as WAV entirely in memory.
pub fn encode_wav_samples(samples: &[f32]) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    {
        let cursor = Cursor::new(&mut bytes);
        let mut writer = WavWriter::new(cursor, wav_spec())?;
        for sample in samples {
            writer.write_sample((sample * i16::MAX as f32) as i16)?;
        }
        writer.finalize()?;
    }
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn in_memory_wav_round_trip() {
        let samples = vec![-0.5, 0.0, 0.5];
        let bytes = encode_wav_samples(&samples).unwrap();
        let decoded = read_wav_samples_from_bytes(&bytes).unwrap();

        assert_eq!(decoded.len(), samples.len());
        for (actual, expected) in decoded.iter().zip(samples) {
            assert!((actual - expected).abs() < 0.0001);
        }
    }

    #[test]
    fn empty_and_near_zero_input_are_silent() {
        assert!(is_effectively_silent(&[]));
        assert!(is_effectively_silent(&[
            0.0,
            SILENT_INPUT_PEAK / 2.0,
            -SILENT_INPUT_PEAK,
        ]));
    }

    #[test]
    fn quiet_but_usable_input_is_not_silent() {
        assert!(!is_effectively_silent(&[0.0, SILENT_INPUT_PEAK * 1.1,]));
        assert!(!is_effectively_silent(&[0.0, -0.1, 0.25]));
    }
}
