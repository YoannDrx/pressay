# Building Pressay

Pressay currently targets macOS 14 or newer on Apple Silicon. The inherited
cross-platform core remains in the repository where keeping it compilable is
low-cost, but Linux, Windows, and Intel builds are not release targets.

## Prerequisites

- Xcode Command Line Tools
- Bun `1.2.19` (see `.bun-version`)
- the Rust toolchain declared by the project
- CMake

## Development

```bash
bun install --frozen-lockfile
bun tauri dev --config src-tauri/tauri.updater.conf.json --features updater
```

The updater configuration is explicit so the Store variant cannot accidentally
inherit updater permissions.

The repository's Cargo configuration sets `GGML_NATIVE=OFF` for transcribe.cpp.
This avoids compiling CPU instructions detected only on the build host and avoids
running hardware probes during configuration. Metal remains enabled. Do not
override this setting with host-specific CPU flags when producing a distributed
Apple Silicon binary; native acceptance on the oldest supported Mac is still
required.

## Verification

```bash
bun run lint
bun run build
bun run check:translations
bun run format:check
cargo fmt --manifest-path src-tauri/Cargo.toml --all -- --check
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets --features updater
cargo test --manifest-path src-tauri/Cargo.toml --all-targets --features updater
```

## Direct distribution build

```bash
bun tauri build --target aarch64-apple-darwin \
  --config src-tauri/tauri.updater.conf.json \
  --features updater
```

Signing, notarization, updater signing, and publication are performed only by
the tagged release workflow. See `docs/RELEASES.md`.

## Mac App Store candidate

```bash
PRESSAY_BUILD_ENVIRONMENT=staging-mac-app-store \
VITE_DISTRIBUTION_CHANNEL=app-store \
CMAKE_POLICY_VERSION_MINIMUM=3.5 \
bun tauri build --target aarch64-apple-darwin \
  --config src-tauri/tauri.appstore.conf.json \
  --features storekit-purchases --bundles app
```

This selects the Sandbox backend and enables StoreKit in the sandboxed variant.
Its dependency graph excludes NSPanel and private Tauri APIs. The base Store
configuration has no signing identity: distribution additionally needs the
matching Apple certificate, provisioning profile and a new bundle build number.
A successful build does not certify purchase/restore, inter-app paste or export
compliance. See `docs/MAC_APP_STORE_SPIKE.md` and
`docs/PRE_SALE_REMEDIATION_2026-09-07.md` for the remaining release conditions.

Release builds emit a separate `pressay.dSYM` containing crash line information.
Keep it with the exact binary: rebuilding the same source can change its UUID.
CI checks the UUID and preserves the symbols as an artifact.

After building with the distribution signing identity and embedding the matching
provisioning profile, package a Store candidate with Python 3:

```bash
python3 scripts/package-macos-store.py \
  src-tauri/target/aarch64-apple-darwin/release/bundle/macos/Pressay.app \
  src-tauri/target/aarch64-apple-darwin/release/pressay.dSYM \
  /absolute/path/to/a-new-candidate-directory \
  --installer-identity '3rd Party Mac Developer Installer: YOUR NAME (TEAM ID)'
```

The script checks the signature, profile, entitlements and matching symbols,
then creates a signed `.pkg` and a `.xcarchive` containing the app and dSYM.
It refuses to overwrite existing candidates and does not upload anything.
Open the archive in Xcode Organizer to validate it and distribute an internal
TestFlight candidate. Retain the archive and its checksums after uploading.
