# Pressay model catalogue

Pressay 2.0 launches with exactly three local presets. A release must fail
closed if the catalogue signature, artifact size, SHA-256, licence record, or
Pressay CDN path is missing.

| Preset   | Model                       | Public catalogue ID     | Default artifact | Terms     |
| -------- | --------------------------- | ----------------------- | ---------------- | --------- |
| Fast     | NVIDIA Parakeet TDT 0.6B v3 | `pressay/parakeet-v3`   | Q8_0             | CC BY 4.0 |
| Polyglot | OpenAI Whisper Small        | `pressay/whisper-small` | Q8_0             | MIT       |
| Precise  | OpenAI Whisper Large v3     | `pressay/whisper-large` | Q5_K_M           | MIT       |

Primary licence evidence:

- NVIDIA's model card states that Parakeet TDT 0.6B v3 is governed by CC BY
  4.0, supports 25 European languages, and is ready for commercial and
  non-commercial use: <https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3>.
- OpenAI states that Whisper's code and model weights are released under the
  MIT licence: <https://github.com/openai/whisper#license> and
  <https://github.com/openai/whisper/blob/main/LICENSE>.

These records document the base weights. Before an artifact is uploaded, the
release operator must also retain the conversion recipe, converter version,
source-weight revision, and any converter notice in the private release
evidence. The SHA-256 in `catalog.json` identifies the exact resulting GGUF.

## Trust chain

The app verifies the detached Ed25519 signature in `catalog.sig` over the exact
bytes of `catalog.json` before parsing it. The public key is embedded as
`catalog.pub`; its SHA-256 fingerprint is:

```text
f78495a531f1284f6909bb696a4da4d37c8e79efb6efb44e5453b95f7a1ee4e0
```

The private key is not stored in Git. It is available to release automation as
the GitHub Actions secret `PRESSAY_MODEL_CATALOG_SIGNING_KEY` and to the local
release Mac in Keychain service `app.pressay.models.signing`. Rotate it by
shipping a new public key in an app release before signing a catalogue with the
new private key.

After changing the JSON, sign it and run the focused verification:

```bash
bun run models:sign
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
cargo test --manifest-path src-tauri/Cargo.toml catalog::tests --features updater
```

A modified JSON with an old signature must cause app startup and tests to fail.

## Storage and publication

Production objects live under the immutable key:

```text
pressay/<preset>/v1/<filename>
```

and are served from `https://models.press-say.app`. The app never needs a
third-party model registry to download its launch presets.

Populate storage only from a local directory containing reviewed artifacts:

```bash
uv run scripts/mirror_models.py --execute --source-dir /secure/audited-models
uv run scripts/mirror_models.py --verify
```

The publisher validates size and SHA-256 before upload, writes immutable cache
headers, and refuses an existing object whose recorded digest differs. DNS,
the R2 bucket, CORS, lifecycle rules, and access credentials must be provisioned
before download testing; a catalogue PR alone does not prove that an artifact
is reachable.

## Adding an advanced model

An advanced model is eligible only after all of the following are attached to
its PR:

1. commercial-use and redistribution terms from a primary source;
2. required attribution text and an About-screen entry;
3. immutable source-weight and conversion revisions;
4. one reviewed default artifact with byte size and SHA-256;
5. Apple Silicon benchmark results on the minimum M1 8 GB target;
6. install, resume, cancel, load, transcribe, and delete test evidence;
7. signed catalogue update and successful mirror verification.

Models with non-commercial, custom, unclear, or missing terms remain excluded.
