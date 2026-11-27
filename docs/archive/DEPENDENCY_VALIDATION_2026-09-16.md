# Dependency validation — 16 September 2026

This batch integrates the native Dependabot proposals #50–#61, #86 and #87 together, preserving their changes in one tested tree. React and React DOM use the same React 19 version; their type packages are upgraded together. Explicit initial ref values and nullable DOM refs follow the [React 19 migration guide](https://react.dev/blog/2024/04/25/react-19-upgrade-guide). The Bun lockfile and generated Nix dependency inventory are regenerated.

SHA-2 0.11 requires the compatible HKDF 0.13 ([RustCrypto documentation](https://docs.rs/hkdf/0.13.0/hkdf/)). Model digests retain lowercase hexadecimal encoding. Fixed synthetic HKDF-SHA256 vectors calculated independently with Python hmac/hashlib verify the existing v1 sync/recovery derivations, in addition to the encryption/decryption tests. No encryption format, key material, stored data, permissions or commercial gate changes.

Local validation: frontend build, lint, 15 Bun unit tests, 16 Chromium UI scenarios, 335 Rust library tests in production-direct release configuration, release Clippy with all targets and warnings denied. Formatting and translations are also checked before commit. GitHub CI validates the remaining native variants and full bundles before merge.

The account production candidate workflow is inherited from PR 96. It must run on merged main, and its final verified DMG is required for installation; no notarization or Gatekeeper check is bypassed.
