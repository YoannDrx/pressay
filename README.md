# Pressay

Pressay is a local-first dictation app for Apple Silicon Macs. Hold a shortcut,
speak, and Pressay transcribes locally before inserting the result in the active
application.

Pressay is being rebuilt from the Handy codebase. The desktop application is
developed in this public source repository. Pressay Cloud, billing
infrastructure, operational configuration, signing material, and product
secrets remain private. Source attribution is documented in [NOTICE](NOTICE);
the Pressay repository has no Handy Git remote.

## Product principles

- Local transcription works without an account or network connection.
- BYOK providers are optional; Keychain migration is a mandatory release gate.
- Pressay Cloud is always explicit and never a silent fallback.
- Transcription history is disabled by default.
- No behavioural analytics are collected.
- The supported launch target is macOS 14 or newer on Apple Silicon.

## Current status

The repository is on the Pressay 2.0 foundation milestone. Local dictation is
inherited from Handy and is being hardened before Cloud, billing, sync, and the
Mac App Store distribution are enabled.

Do not ship the current `main` branch as a commercial release. Release gates and
the distribution split are documented in [docs/RELEASES.md](docs/RELEASES.md).

## Development

Prerequisites:

- Apple Silicon Mac for supported runtime testing
- macOS 14 or newer
- latest stable Rust
- Bun
- Xcode command-line tools

Install dependencies and run the app:

```bash
bun install --frozen-lockfile
mkdir -p src-tauri/resources/models
curl -o src-tauri/resources/models/silero_vad_v4.onnx \
  https://models.press-say.app/silero_vad_v4.onnx
CMAKE_POLICY_VERSION_MINIMUM=3.5 bun run tauri dev \
  --config src-tauri/tauri.updater.conf.json \
  --features updater
```

The signed Pressay model catalogue, licence evidence, signing procedure, and
mirror publication gates are documented in [docs/MODELS.md](docs/MODELS.md).
The mirror must be populated from audited artifacts before model download
testing or any production release.

The E2EE key hierarchy, recovery-code protocol, excluded data, and remaining
operational checks are documented in [docs/CLOUD_SYNC.md](docs/CLOUD_SYNC.md).

Run the smallest complete local verification set:

```bash
bun run check:translations
bun run lint
bun run format:check
bun run build
(cd src-tauri && cargo test --features updater)
```

## CLI

The packaged executable is `pressay`:

```bash
pressay --toggle-transcription
pressay --toggle-post-process
pressay --cancel
pressay --start-hidden
pressay --list-models
pressay --list-devices
```

## Repository workflow

- `origin` is the only push destination.
- Direct pushes to `main` are prohibited.
- Work is submitted from `codex/<topic>` branches through pull requests.
- No automatic or manual Git synchronization with Handy is part of the Pressay
  workflow.

## Security and privacy

Do not include transcripts, audio, selected text, clipboard contents, prompts,
access tokens, or provider keys in logs, issues, screenshots, crash reports, or
test fixtures. See [SECURITY.md](SECURITY.md) for reporting and handling rules.

## License

The Handy-derived desktop code retains the upstream MIT license and copyright.
Pressay branding, services, infrastructure, and commercial assets are not
granted by that license. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
