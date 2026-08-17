use anyhow::{anyhow, bail, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use chacha20poly1305::{
    aead::{Aead, Generate, KeyInit},
    Key, XChaCha20Poly1305, XNonce,
};
use hkdf::Hkdf;
use rand_core::OsRng;
use sha2::{Digest, Sha256};
use x25519_dalek::{PublicKey, StaticSecret};

const SEALED_KEY_MAGIC: &[u8; 8] = b"PRSYSK01";
const SYNC_DATA_MAGIC: &[u8; 8] = b"PRSYSY01";
const RECOVERY_KEY_MAGIC: &[u8; 8] = b"PRSYRC01";
const RECOVERY_CODE_PREFIX: &str = "PRS1";
const PUBLIC_KEY_LEN: usize = 32;
const NONCE_LEN: usize = 24;
pub const KEY_LEN: usize = 32;

pub fn generate_device_keypair() -> ([u8; KEY_LEN], [u8; PUBLIC_KEY_LEN]) {
    let private = StaticSecret::random_from_rng(OsRng);
    let public = PublicKey::from(&private);
    (private.to_bytes(), public.to_bytes())
}

pub fn device_public_key(private: &[u8; KEY_LEN]) -> [u8; PUBLIC_KEY_LEN] {
    PublicKey::from(&StaticSecret::from(*private)).to_bytes()
}

pub fn generate_account_key() -> [u8; KEY_LEN] {
    Key::generate().into()
}

fn recovery_secret(code: &str) -> Result<[u8; KEY_LEN]> {
    let compact = code.split_ascii_whitespace().collect::<String>();
    let (prefix, encoded) = compact
        .split_once('.')
        .ok_or_else(|| anyhow!("Invalid recovery code"))?;
    if prefix != RECOVERY_CODE_PREFIX || encoded.contains('.') {
        bail!("Invalid recovery code");
    }
    URL_SAFE_NO_PAD
        .decode(encoded)
        .map_err(|_| anyhow!("Invalid recovery code"))?
        .try_into()
        .map_err(|_| anyhow!("Invalid recovery code"))
}

fn recovery_wrapping_key(secret: &[u8; KEY_LEN]) -> Result<[u8; KEY_LEN]> {
    let mut output = [0_u8; KEY_LEN];
    Hkdf::<Sha256>::new(Some(b"Pressay sync recovery v1"), secret)
        .expand(b"account key envelope", &mut output)
        .map_err(|_| anyhow!("Unable to derive recovery wrapping key"))?;
    Ok(output)
}

fn format_recovery_code(secret: &[u8; KEY_LEN]) -> String {
    let encoded = URL_SAFE_NO_PAD.encode(secret);
    let grouped = encoded
        .as_bytes()
        .chunks(5)
        .map(|chunk| std::str::from_utf8(chunk).expect("base64url is UTF-8"))
        .collect::<Vec<_>>()
        .join(" ");
    format!("{RECOVERY_CODE_PREFIX}.{grouped}")
}

pub fn recovery_code_hash(code: &str) -> Result<[u8; KEY_LEN]> {
    let mut secret = recovery_secret(code)?;
    let hash: [u8; KEY_LEN] = Sha256::digest(secret).into();
    secret.fill(0);
    Ok(hash)
}

pub fn create_recovery_envelope(
    account_key: &[u8; KEY_LEN],
) -> Result<(String, [u8; KEY_LEN], Vec<u8>)> {
    let mut secret: [u8; KEY_LEN] = Key::generate().into();
    let code = format_recovery_code(&secret);
    let code_hash: [u8; KEY_LEN] = Sha256::digest(secret).into();
    let mut wrapping_key = recovery_wrapping_key(&secret)?;
    let nonce = XNonce::generate();
    let ciphertext = XChaCha20Poly1305::new(&Key::from(wrapping_key))
        .encrypt(
            &nonce,
            chacha20poly1305::aead::Payload {
                msg: account_key,
                aad: RECOVERY_KEY_MAGIC,
            },
        )
        .map_err(|_| anyhow!("Unable to encrypt recovery envelope"))?;
    secret.fill(0);
    wrapping_key.fill(0);
    let mut envelope = Vec::with_capacity(RECOVERY_KEY_MAGIC.len() + NONCE_LEN + ciphertext.len());
    envelope.extend_from_slice(RECOVERY_KEY_MAGIC);
    envelope.extend_from_slice(&nonce);
    envelope.extend_from_slice(&ciphertext);
    Ok((code, code_hash, envelope))
}

pub fn open_recovery_envelope(code: &str, envelope: &[u8]) -> Result<[u8; KEY_LEN]> {
    if envelope.len() != RECOVERY_KEY_MAGIC.len() + NONCE_LEN + KEY_LEN + 16
        || &envelope[..RECOVERY_KEY_MAGIC.len()] != RECOVERY_KEY_MAGIC
    {
        bail!("Unsupported recovery envelope");
    }
    let nonce_end = RECOVERY_KEY_MAGIC.len() + NONCE_LEN;
    let nonce = XNonce::try_from(&envelope[RECOVERY_KEY_MAGIC.len()..nonce_end])
        .map_err(|_| anyhow!("Unsupported recovery envelope"))?;
    let mut secret = recovery_secret(code)?;
    let mut wrapping_key = recovery_wrapping_key(&secret)?;
    let plaintext = XChaCha20Poly1305::new(&Key::from(wrapping_key))
        .decrypt(
            &nonce,
            chacha20poly1305::aead::Payload {
                msg: &envelope[nonce_end..],
                aad: RECOVERY_KEY_MAGIC,
            },
        )
        .map_err(|_| anyhow!("Unable to decrypt recovery envelope"));
    secret.fill(0);
    wrapping_key.fill(0);
    plaintext?
        .try_into()
        .map_err(|_| anyhow!("Invalid recovery account key"))
}

fn wrapping_key(
    shared_secret: &[u8; KEY_LEN],
    ephemeral_public: &[u8; PUBLIC_KEY_LEN],
    recipient_public: &[u8; PUBLIC_KEY_LEN],
) -> Result<[u8; KEY_LEN]> {
    let mut output = [0_u8; KEY_LEN];
    Hkdf::<Sha256>::new(Some(b"Pressay sync key wrapping v1"), shared_secret)
        .expand(
            &[ephemeral_public.as_slice(), recipient_public.as_slice()].concat(),
            &mut output,
        )
        .map_err(|_| anyhow!("Unable to derive sync wrapping key"))?;
    Ok(output)
}

pub fn seal_account_key(
    account_key: &[u8; KEY_LEN],
    recipient_public: &[u8; PUBLIC_KEY_LEN],
) -> Result<Vec<u8>> {
    let ephemeral_private = StaticSecret::random_from_rng(OsRng);
    let ephemeral_public = PublicKey::from(&ephemeral_private).to_bytes();
    let shared = ephemeral_private
        .diffie_hellman(&PublicKey::from(*recipient_public))
        .to_bytes();
    let key = wrapping_key(&shared, &ephemeral_public, recipient_public)?;
    let nonce = XNonce::generate();
    let ciphertext = XChaCha20Poly1305::new(&Key::from(key))
        .encrypt(
            &nonce,
            chacha20poly1305::aead::Payload {
                msg: account_key,
                aad: SEALED_KEY_MAGIC,
            },
        )
        .map_err(|_| anyhow!("Unable to seal sync account key"))?;
    let mut envelope = Vec::with_capacity(SEALED_KEY_MAGIC.len() + 32 + 24 + ciphertext.len());
    envelope.extend_from_slice(SEALED_KEY_MAGIC);
    envelope.extend_from_slice(&ephemeral_public);
    envelope.extend_from_slice(&nonce);
    envelope.extend_from_slice(&ciphertext);
    Ok(envelope)
}

pub fn open_account_key(
    envelope: &[u8],
    recipient_private: &[u8; KEY_LEN],
) -> Result<[u8; KEY_LEN]> {
    if envelope.len() != SEALED_KEY_MAGIC.len() + PUBLIC_KEY_LEN + NONCE_LEN + KEY_LEN + 16
        || &envelope[..SEALED_KEY_MAGIC.len()] != SEALED_KEY_MAGIC
    {
        bail!("Unsupported sync key envelope");
    }
    let public_start = SEALED_KEY_MAGIC.len();
    let nonce_start = public_start + PUBLIC_KEY_LEN;
    let ciphertext_start = nonce_start + NONCE_LEN;
    let ephemeral_public: [u8; PUBLIC_KEY_LEN] = envelope[public_start..nonce_start]
        .try_into()
        .map_err(|_| anyhow!("Unsupported sync key envelope"))?;
    let private = StaticSecret::from(*recipient_private);
    let recipient_public = PublicKey::from(&private).to_bytes();
    let shared = private
        .diffie_hellman(&PublicKey::from(ephemeral_public))
        .to_bytes();
    let key = wrapping_key(&shared, &ephemeral_public, &recipient_public)?;
    let nonce = XNonce::try_from(&envelope[nonce_start..ciphertext_start])
        .map_err(|_| anyhow!("Unsupported sync key envelope"))?;
    let plaintext = XChaCha20Poly1305::new(&Key::from(key))
        .decrypt(
            &nonce,
            chacha20poly1305::aead::Payload {
                msg: &envelope[ciphertext_start..],
                aad: SEALED_KEY_MAGIC,
            },
        )
        .map_err(|_| anyhow!("Unable to open sync account key"))?;
    plaintext
        .try_into()
        .map_err(|_| anyhow!("Invalid sync account key"))
}

pub fn encrypt_change(
    account_key: &[u8; KEY_LEN],
    plaintext: &[u8],
    aad: &[u8],
) -> Result<Vec<u8>> {
    let nonce = XNonce::generate();
    let ciphertext = XChaCha20Poly1305::new(&Key::from(*account_key))
        .encrypt(
            &nonce,
            chacha20poly1305::aead::Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|_| anyhow!("Unable to encrypt sync change"))?;
    let mut envelope = Vec::with_capacity(SYNC_DATA_MAGIC.len() + NONCE_LEN + ciphertext.len());
    envelope.extend_from_slice(SYNC_DATA_MAGIC);
    envelope.extend_from_slice(&nonce);
    envelope.extend_from_slice(&ciphertext);
    Ok(envelope)
}

pub fn decrypt_change(account_key: &[u8; KEY_LEN], envelope: &[u8], aad: &[u8]) -> Result<Vec<u8>> {
    if envelope.len() < SYNC_DATA_MAGIC.len() + NONCE_LEN + 16
        || &envelope[..SYNC_DATA_MAGIC.len()] != SYNC_DATA_MAGIC
    {
        bail!("Unsupported encrypted sync change");
    }
    let nonce_end = SYNC_DATA_MAGIC.len() + NONCE_LEN;
    let nonce = XNonce::try_from(&envelope[SYNC_DATA_MAGIC.len()..nonce_end])
        .map_err(|_| anyhow!("Unsupported encrypted sync change"))?;
    XChaCha20Poly1305::new(&Key::from(*account_key))
        .decrypt(
            &nonce,
            chacha20poly1305::aead::Payload {
                msg: &envelope[nonce_end..],
                aad,
            },
        )
        .map_err(|_| anyhow!("Unable to decrypt sync change"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn account_key_is_bound_to_the_recipient_device() {
        let account_key = generate_account_key();
        let (private, public) = generate_device_keypair();
        let (wrong_private, _) = generate_device_keypair();
        let envelope = seal_account_key(&account_key, &public).unwrap();
        assert_eq!(open_account_key(&envelope, &private).unwrap(), account_key);
        assert!(open_account_key(&envelope, &wrong_private).is_err());
        assert!(!envelope
            .windows(account_key.len())
            .any(|part| part == account_key));
    }

    #[test]
    fn device_public_key_is_stable_for_the_keychain_secret() {
        let (private, public) = generate_device_keypair();
        assert_eq!(device_public_key(&private), public);
    }

    #[test]
    fn recovery_code_round_trip_is_local_and_whitespace_tolerant() {
        let account_key = generate_account_key();
        let (code, code_hash, envelope) = create_recovery_envelope(&account_key).unwrap();
        assert!(code.starts_with("PRS1."));
        assert_eq!(recovery_code_hash(&code).unwrap(), code_hash);
        assert_eq!(
            open_recovery_envelope(&format!("  {code}  \n"), &envelope).unwrap(),
            account_key
        );
        assert!(!envelope
            .windows(account_key.len())
            .any(|part| part == account_key));
    }

    #[test]
    fn recovery_envelope_rejects_a_different_code_and_bad_format() {
        let account_key = generate_account_key();
        let (_, _, envelope) = create_recovery_envelope(&account_key).unwrap();
        let (wrong_code, _, _) = create_recovery_envelope(&account_key).unwrap();
        assert!(open_recovery_envelope(&wrong_code, &envelope).is_err());
        assert!(recovery_code_hash("PRS1.not-valid").is_err());
        assert!(recovery_code_hash("not-a-pressay-code").is_err());
    }

    #[test]
    fn sync_changes_require_the_same_object_context() {
        let key = generate_account_key();
        let envelope = encrypt_change(&key, b"private settings", b"mode:id:revision:1").unwrap();
        assert_eq!(
            decrypt_change(&key, &envelope, b"mode:id:revision:1").unwrap(),
            b"private settings"
        );
        assert!(decrypt_change(&key, &envelope, b"profile:id:revision:1").is_err());
    }
}
