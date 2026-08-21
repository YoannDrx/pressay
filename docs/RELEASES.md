# Pressay distribution channels

Pressay has two independently gated macOS distributions.

## Direct DMG

- Bundle ID: `app.pressay.desktop`
- Minimum system: macOS 14
- Architecture: Apple Silicon (`aarch64-apple-darwin`)
- Developer ID signing, hardened runtime, notarization, and stapling required
- Pressay updater enabled and signed with the repository updater key
- Stripe/web billing may be exposed after the Cloud gate passes

Tags matching `v*` may start the DMG workflow. The workflow must fail before
building if Apple signing or notarization secrets are absent.

## Mac App Store

- Bundle ID: `fr.yodev.pressay`
- App Sandbox required
- No Tauri self-updater
- No Stripe checkout or external purchase call-to-action
- StoreKit purchase and restore required before submission
- Dedicated entitlements and provisioning profile

The Store build uses `src-tauri/tauri.appstore.conf.json` as an override. A
successful DMG release does not imply that the Store build is ready. It must be
built with `--features mas`; CI rejects any Store dependency graph containing
`tauri-nspanel` or Tauri's `macos-private-api` feature.

## Release gates

Do not publish a public beta until branding, secrets, logs, history, paste,
model licences, updater ownership, privacy policy, and account deletion have
their dedicated acceptance tests. Pressay Cloud and Mac App Store each have an
independent kill switch and release decision.
