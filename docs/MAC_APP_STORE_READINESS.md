# Mac App Store readiness

## Decision

Pressay can be prepared for the Mac App Store, but submission is not yet an
automatic release decision. The sandboxed binary, StoreKit flow and native
cross-application behavior must all pass with Apple-issued development and
distribution profiles before the first review.

## Implemented in the repository

- Separate bundle identifier: `fr.yodev.pressay`, aligned with the existing
  Pressay App Store Connect record.
- Separate `mas` feature graph without Tauri private macOS APIs or NSPanel.
- App Sandbox, audio-input, network-client and user-selected-file entitlements.
- StoreKit 2 product loading, purchase, on-device transaction verification,
  explicit Restore Purchases and background entitlement reconciliation.
- On macOS 15.2 and later, the StoreKit confirmation sheet is explicitly
  attached to the active Pressay AppKit window; macOS 14 uses Apple's compatible
  generic purchase API because the window-attached overload is unavailable.
- Authenticated server verification of the StoreKit JWS and exact
  `appAccountToken` match to the Pressay account UUID.
- Local StoreKit configuration for monthly and annual Pressay Pro products.
- Stripe and updater surfaces remain separate from the MAS purchase path.
- CI feasibility job builds the MAS graph, ad-hoc signs the bundle and rejects
  private API features or unexpected entitlements.
- A separate protected archive workflow imports the application and installer
  identities into an ephemeral keychain, embeds the provisioning profile,
  signs and packages the app, rechecks the public feature boundary, and can
  validate/upload the resulting package with an App Store Connect API key.
  The Store-signed package is checked with `pkgutil` and then with Apple's
  `altool`; unlike a notarized Direct package, it is not expected to pass a
  local Gatekeeper distribution assessment before App Store processing.

## Acceptance risks to validate natively

### Accessibility and global shortcut

Pressay uses a user-configured global shortcut and Accessibility permission to
insert text into the active application. These are central, user-visible
features rather than background surveillance, but they need explicit App Review
notes and a working demonstration. Test the Apple-signed sandbox build with
Accessibility both denied and granted; the local dictation path must never enter
an onboarding loop.

### Cross-application insertion

Test paste, direct typing, selected-text rewrite and clipboard restoration in
Mail, Messages, Notes, Safari, Chrome, Slack, Notion, Word, Cursor, Terminal and
secure fields. If the sandbox prevents reliable insertion, the MAS channel must
ship an explicit copy-only workflow and its product page must not promise
automatic insertion. Do not silently degrade.

### Model downloads and files

Downloaded models must remain inside the app container. File transcription and
import/export must use standard user-selected open/save panels so sandbox access
is granted by the user. No broad filesystem temporary exception should be added.

## Subscription review

Create one subscription group named `Pressay Pro` with the immutable products:

- `app.pressay.desktop.mas.pro.monthly` — one month;
- `app.pressay.desktop.mas.pro.annual` — one year.

Use Apple-localized price tiers rather than hard-coded client prices. The first
auto-renewable subscriptions must be submitted with the first app version. Add
review screenshots and notes that explain the ongoing Pro value: advanced voice
commands, modes, BYOK, encrypted synchronization and explicit Cloud allowance.
The free local dictation tier remains usable without an account or subscription.

## App Store Connect external gates

- Active Apple Developer Program membership and accepted agreements.
- Registered MAS bundle ID and App Store Connect app record.
- Apple Distribution certificate and matching MAS provisioning profile.
- Mac Installer Distribution certificate for the upload package.
- App Store Connect API key stored only in the protected release environment.
- App Store Server API key and Notifications V2 URLs configured in Cloud.
- Paid Applications agreement, banking and tax forms complete.
- FR/EN name, subtitle, description, keywords, screenshots, privacy answers,
  support URL, privacy URL and review contact complete.
- A review account that reaches Pro without exposing a shared password in the
  binary or repository.

Prepared, non-published submission copy lives under [`docs/app-store`](app-store/):
FR/EN metadata, review notes and the conservative privacy/accessibility draft.
Those files intentionally retain explicit native, legal and owner-completion
placeholders rather than claiming a capability that has not passed Sandbox.

## Required test sequence

1. Run StoreKit Configuration locally: purchase, pending, cancellation,
   unverified response, renewal, billing issue, refund and restore.
2. Run the Apple-signed Development MAS build on macOS 14 and current macOS.
3. Validate the full dictation and insertion matrix in the App Sandbox.
4. Configure Sandbox products and server notification endpoints.
5. Test with Sandbox Apple IDs, then upload to TestFlight.
6. Repeat purchase, restore, expiration, refund, device change and account
   mismatch in TestFlight.
7. Submit the stable app and both first subscriptions together with precise
   review notes and a short screen recording of the shortcut and permissions.

The protected GitHub environment is named `app-store-production`. Its required
secrets are documented by the variable names in
`.github/workflows/app-store-release.yml`; the workflow cannot run from a branch
other than `main`, and upload is a separate explicit input.

## Sources

- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Apple subscription setup: https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/
- Apple build upload requirements: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- Tauri App Store bundling: https://v2.tauri.app/distribute/
- Tauri macOS signing: https://v2.tauri.app/distribute/sign/macos/
