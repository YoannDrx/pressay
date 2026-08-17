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

## Mac App Store spike

```bash
bun tauri build --target aarch64-apple-darwin \
  --config src-tauri/tauri.appstore.conf.json
```

This produces the sandbox proof bundle without the Tauri updater. It is not a
release-ready Store build while the inherited NSPanel/private-API dependency is
present. See `docs/MAC_APP_STORE_SPIKE.md` for the blocking matrix.
