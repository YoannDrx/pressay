# App Review notes — candidate 2.0.0 (2.0.4), not yet submitted

## Product boundary

Pressay is a macOS local-first dictation application. Its Free tier can be used
without an account and, after downloading a model, without a network connection.
The Mac App Store candidate uses
App Sandbox, StoreKit and Apple-delivered updates; it contains no Stripe checkout,
external purchase call-to-action or direct updater.

## How to test the core workflow

1. Launch Pressay and continue locally.
2. Grant Microphone when the app explains the request.
3. Grant Accessibility from System Settings when prompted. Pressay uses it only
   to verify the current target and insert the text requested by the user.
4. Download the recommended local model.
5. Put the cursor in the provided onboarding field or a Notes document.
6. Hold the shortcut shown by Pressay, speak, then release.
7. Verify that the Voice Bar changes from listening to transcribing and that the
   result is inserted or explicitly offered for copying.

The shortcut displayed in the UI is dynamic. Do not assume Command; the default
under review is the binding packaged in the submitted build.

## Accounts and purchases

The local workflow requires no account. To review Pro, open Account and sign in
with Apple using an Apple review/test account. No shared password or hidden
entitlement is required. The production sign-in configuration advertises Apple.
Native sign-in and purchases on the Apple-delivered candidate remain release gates.

- Subscription group: `Pressay Pro`
- Monthly: `app.pressay.desktop.mas.pro.monthly`
- Annual: `app.pressay.desktop.mas.pro.annual`
- No free trial and no lifetime product.
- After signing in, choose an Apple subscription from Account.
- Restore Purchases is available from Account, including when product loading fails.
- Cancel the purchase sheet and confirm that Free remains available.
- After a Sandbox purchase, relaunch, restore and verify Pro. Also exercise
  interrupted purchases, renewal, expiration and refund with the Apple test tools.

Build 2.0.4 uses the production Pressay backend. Since 10 September 2026 it verifies
both Apple Production and Sandbox transactions against the corresponding Apple
server. Sandbox records are isolated, cannot overwrite real purchases and expire
at Apple's verified expiration without the commercial offline grace period.
Both Apple notification URLs point to `https://api.press-say.app/v1/webhooks/apple`.
The server database tests cover activation, collision isolation, duplicate events,
expiration and refund; they do not replace native signed purchase/restore testing.

## Reviewer context

Pressay rejects secure text fields before opening the microphone. The local route
continues to work when the account or Cloud is unavailable. Any route that sends
content off the Mac is named explicitly before use. Attach a short privacy-safe
screen recording demonstrating the shortcut, both permission prompts, StoreKit
purchase/restore and the copy-only fallback if that fallback ships.

## Final placeholders

- Review contact saved in App Store Connect: Yoann Andrieux; email and phone confirmed.
- Review account: reviewer/tester signs in with Apple; native flow must pass before submission.
- Video URL: `ADD AFTER APPLE-SIGNED SANDBOX VALIDATION`
- Hardware/macOS versions tested: `ADD FROM NATIVE RELEASE MATRIX`

## Current submission gate (10 September 2026)

The current 2.0.4 archive includes main `f5d06c6` and the audited recovery fixes.
It declares `ITSAppUsesNonExemptEncryption=true`. Xcode rejected its upload with
`Invalid Export Compliance Code` (ID `078d88f1-e0e8-42dd-9842-f8b9376504da`).
The document `pressay-anssi-declaration-signed.pdf`, uploaded 23 August, remains
in Apple's verification state without a key. Do not remove the encryption
classification or invent an exemption to bypass this gate.

The older build 2.0.3 (ID `92cac7fa-ca9f-4895-ba23-c2daef7f42b4`) was processed
and attached earlier, but is superseded and has been detached from the draft
version. Rebuild with
the approved compliance key, upload and select the new candidate before review.
No TestFlight installation, native purchase/restore, or App Review submission
is claimed for either candidate.
