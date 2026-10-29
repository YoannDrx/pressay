# Pressay distribution channels

Pressay has two independently gated macOS distributions and a Windows build.

## Direct DMG

- Bundle ID: `app.pressay.desktop`
- Minimum system: macOS 14
- Architecture: Apple Silicon (`aarch64-apple-darwin`)
- Developer ID signing, hardened runtime, notarization, and stapling required
- Pressay updater enabled and signed with the repository updater key
- Stripe/web billing may be exposed after the Cloud gate passes

### Update endpoints

Clients ask `https://updates.press-say.app/{{target}}/{{arch}}/{{current_version}}`,
served by pressay-web. It returns the `latest.json` of the newest published
release, or `204` when the client is current. A client on a prerelease is
offered betas and stables; a stable client is only offered stables. GitHub's
`releases/latest/download/latest.json` is the fallback when that endpoint fails.

Every public beta up to 2.0.0-beta.4 was built against
`https://updates.press-say.app/latest.json`. pressay-web keeps that path alive
and serves the newest manifest, betas included, so those installs can update
once a release carries `latest.json`. Releases built before the updater
verification job (beta.1 to beta.4) carry no `latest.json` and are never
offered.

Tags matching `v*` may start the DMG workflow. The workflow must fail before
building if Apple signing or notarization secrets are absent.

## Windows

- Targets: Windows 10 22H2 and Windows 11, `x86_64-pc-windows-msvc` and
  `aarch64-pc-windows-msvc`
- NSIS installer, per-user install, WebView2 bootstrapper embedded
- Same updater key and `latest.json` as the DMG (`windows-x86_64`,
  `windows-aarch64`); the NSIS installer is the update payload
- Canonical download assets: `Pressay-windows-x64.exe`,
  `Pressay-windows-arm64.exe` and their `.sha256`
- Stripe/web billing like the DMG; no Microsoft Store build yet

The release workflow builds Windows only when the repository variable
`WINDOWS_RELEASE_ENABLED` is `true`. That switch requires Authenticode signing:

| Kind     | Name                                                        | Value                                                     |
| -------- | ----------------------------------------------------------- | --------------------------------------------------------- |
| Secret   | `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` | Service principal allowed to sign                         |
| Variable | `AZURE_SIGNING_ENDPOINT`                                    | Region endpoint, e.g. `https://weu.codesigning.azure.net` |
| Variable | `AZURE_SIGNING_ACCOUNT`                                     | Artifact Signing account name                             |
| Variable | `AZURE_SIGNING_PROFILE`                                     | Certificate profile name                                  |

A signed build fails if any of them is missing, and the release refuses an
installer whose Authenticode signature is not valid.

Setting `WINDOWS_AUTHENTICODE` to `false` publishes an unsigned public beta
instead: the update payload is still minisign-signed, but Windows SmartScreen
shows "Windows protected your PC" and Smart App Control may block the
installer. Remove the variable as soon as signing is available; SmartScreen
reputation then builds on the signing identity.

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
