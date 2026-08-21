# App Review notes — draft

## Product boundary

Pressay is a macOS local-first dictation application. Its Free tier can be used
without an account or network connection. The submitted Mac App Store build uses
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

## Accounts and review entitlement

- The local dictation path requires no account.
- A dedicated review account and its credentials must be entered only in App
  Store Connect, never in this repository or in the binary.
- The review account must have a server-side review entitlement that exercises
  Pro without bypassing StoreKit for customers.
- Sign in with Apple and Google are equivalent account options. Sign in with Apple
  must be configured and verified before these notes are submitted.

## StoreKit

- Subscription group: `Pressay Pro`
- Monthly: `app.pressay.desktop.mas.pro.monthly`
- Annual: `app.pressay.desktop.mas.pro.annual`
- No free trial and no lifetime product.
- Restore Purchases is available from Account.

## Reviewer context

Pressay rejects secure text fields before opening the microphone. The local route
continues to work when the account or Cloud is unavailable. Any route that sends
content off the Mac is named explicitly before use. Attach a short privacy-safe
screen recording demonstrating the shortcut, both permission prompts, StoreKit
purchase/restore and the copy-only fallback if that fallback ships.

## Final placeholders

- Review contact: `OWNER TO COMPLETE IN APP STORE CONNECT`
- Review account: `OWNER TO COMPLETE IN APP STORE CONNECT`
- Video URL: `ADD AFTER APPLE-SIGNED SANDBOX VALIDATION`
- Hardware/macOS versions tested: `ADD FROM NATIVE RELEASE MATRIX`
