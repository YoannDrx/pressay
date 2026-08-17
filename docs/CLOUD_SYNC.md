# Pressay encrypted sync

Pressay Cloud synchronizes only modes, application profiles, dictionary entries,
and explicitly allowlisted preferences. Transcripts, audio, history, selected
text, prompts, and BYOK credentials are excluded before encryption.

## Key hierarchy

- Each account has a random 256-bit account key generated on the first Mac.
- Each Mac has an X25519 device key pair. The private key and the decrypted
  account key live only in macOS Keychain.
- The backend stores public device keys, per-device encrypted account-key
  envelopes, and XChaCha20-Poly1305 encrypted sync objects.
- Object metadata is authenticated as additional data so an envelope cannot be
  replayed under a different object type, identifier, revision, or version.

A new Mac normally waits for an already approved Mac to seal the account key to
its public key. The backend cannot perform that operation.

## Recovery code

An approved Mac may create a recovery code. The code contains 256 random bits
and is displayed once. Pressay derives a wrapping key locally with HKDF-SHA256
and encrypts the account key with XChaCha20-Poly1305. The backend receives only:

- SHA-256 of the random recovery secret;
- the opaque encrypted account-key envelope.

During recovery, the backend checks the hash and returns the opaque envelope.
The new Mac decrypts it locally, seals the account key to its own public key,
and completes approval. Completion atomically consumes the recovery code. A new
code replaces the previous code.

The code is never written to settings, logs, sync state, or the backend in clear
text. Copying it is an explicit user action and the UI warns the user to remove
it from the clipboard after saving it.

## Operational gates

The protocol and local cryptographic tests do not replace staging validation.
Before enabling sync commercially, test first-device enrollment, approval,
recovery, code rotation, response loss, device revocation, conflicts, and account
deletion against the production-shaped backend. A third-party security review
remains a Cloud launch gate.
