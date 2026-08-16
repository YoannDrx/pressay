use anyhow::{anyhow, bail, Result};
use chacha20poly1305::{
    aead::{Aead, Generate, KeyInit},
    Key, XChaCha20Poly1305, XNonce,
};

const ENVELOPE_MAGIC: &[u8; 8] = b"PRSYENC1";
const NONCE_LEN: usize = 24;

pub const MASTER_KEY_LEN: usize = 32;

pub fn generate_master_key() -> [u8; MASTER_KEY_LEN] {
    let key = Key::generate();
    key.into()
}

pub fn encrypt(key: &[u8; MASTER_KEY_LEN], plaintext: &[u8], aad: &[u8]) -> Result<Vec<u8>> {
    let key = Key::from(*key);
    let cipher = XChaCha20Poly1305::new(&key);
    let nonce = XNonce::generate();
    let ciphertext = cipher
        .encrypt(
            &nonce,
            chacha20poly1305::aead::Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|_| anyhow!("Unable to encrypt history content"))?;

    let mut envelope = Vec::with_capacity(ENVELOPE_MAGIC.len() + NONCE_LEN + ciphertext.len());
    envelope.extend_from_slice(ENVELOPE_MAGIC);
    envelope.extend_from_slice(&nonce);
    envelope.extend_from_slice(&ciphertext);
    Ok(envelope)
}

pub fn decrypt(key: &[u8; MASTER_KEY_LEN], envelope: &[u8], aad: &[u8]) -> Result<Vec<u8>> {
    if envelope.len() < ENVELOPE_MAGIC.len() + NONCE_LEN
        || &envelope[..ENVELOPE_MAGIC.len()] != ENVELOPE_MAGIC
    {
        bail!("Unsupported encrypted history envelope");
    }

    let nonce_start = ENVELOPE_MAGIC.len();
    let ciphertext_start = nonce_start + NONCE_LEN;
    let nonce = XNonce::try_from(&envelope[nonce_start..ciphertext_start])
        .map_err(|_| anyhow!("Unsupported encrypted history envelope"))?;
    let key = Key::from(*key);
    let cipher = XChaCha20Poly1305::new(&key);
    cipher
        .decrypt(
            &nonce,
            chacha20poly1305::aead::Payload {
                msg: &envelope[ciphertext_start..],
                aad,
            },
        )
        .map_err(|_| anyhow!("Unable to decrypt history content"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn envelope_round_trip_requires_matching_context() {
        let key = generate_master_key();
        let plaintext = b"private transcription";
        let envelope = encrypt(&key, plaintext, b"history:42:transcript").unwrap();

        assert_ne!(envelope, plaintext);
        assert_eq!(
            decrypt(&key, &envelope, b"history:42:transcript").unwrap(),
            plaintext
        );
        assert!(decrypt(&key, &envelope, b"history:43:transcript").is_err());
    }

    #[test]
    fn each_envelope_uses_a_fresh_nonce() {
        let key = generate_master_key();
        let first = encrypt(&key, b"same", b"context").unwrap();
        let second = encrypt(&key, b"same", b"context").unwrap();
        assert_ne!(first, second);
    }

    #[test]
    fn corrupted_envelope_is_rejected() {
        let key = generate_master_key();
        let mut envelope = encrypt(&key, b"content", b"context").unwrap();
        *envelope.last_mut().unwrap() ^= 1;
        assert!(decrypt(&key, &envelope, b"context").is_err());
    }
}
