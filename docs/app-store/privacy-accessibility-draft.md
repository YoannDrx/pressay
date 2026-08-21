# App privacy and accessibility — submission draft

This is a conservative preparation document, not authorization to publish an App
Privacy or Accessibility Nutrition Label. Answers must match the exact submitted
binary and Cloud configuration.

## App Privacy candidates

Local dictation, local history, clipboard content, selected text and BYOK keys are
not transmitted to Pressay in their local/BYOK routes and must not be declared as
Pressay-collected data solely because they exist on the Mac.

The following off-device data types require final disclosure review:

| Data type                       | Current purpose                                      | Linked to identity | Tracking | Release evidence required                                                                         |
| ------------------------------- | ---------------------------------------------------- | ------------------ | -------- | ------------------------------------------------------------------------------------------------- |
| Email address                   | Account creation, authentication and support         | Yes                | No       | Google and Apple account flows                                                                    |
| User ID                         | Account, entitlement, devices and deletion           | Yes                | No       | Cloud schema and deletion test                                                                    |
| Device ID                       | Device approval, quota and revocation                | Yes                | No       | HMAC/pseudonymization review                                                                      |
| Purchase history                | StoreKit entitlement and restore                     | Yes                | No       | Sandbox, refund and deletion behavior                                                             |
| Product interaction             | Optional coarse telemetry only                       | Potentially        | No       | Consent default-off and retention proof                                                           |
| Audio data / other user content | Only an explicitly selected Pressay Cloud operation  | Potentially        | No       | Confirm whether Apple's transient-processing exception applies; otherwise disclose conservatively |
| Crash or diagnostic data        | Technical support only if the shipped build sends it | Depends            | No       | Inspect final binary and network traffic                                                          |

Payment-card data entered into Apple's purchase sheet is handled by Apple and is
not received by Pressay. BYOK provider processing is a user-directed third-party
route and must be described in the privacy policy even when Pressay cannot access
the provider credential.

## Data use rules

- No advertising, cross-app tracking or data-broker use.
- No transcript, audio, clipboard, selection, prompt, response or API key in logs,
  analytics, sync payloads or diagnostic events.
- Remote product telemetry remains off by default and requires explicit consent.
- Privacy Policy URL: `https://press-say.app/en/privacy` (localized FR equivalent).
- Privacy choices URL candidate: `https://press-say.app/account` after account
  export/deletion and consent controls pass staging.

## Accessibility Nutrition Labels

Do not claim a label until every common task — onboarding, permissions, first
dictation, account, purchase, restore and settings — passes with that feature.

| Feature                           | Draft state       | Required evidence                                                          |
| --------------------------------- | ----------------- | -------------------------------------------------------------------------- |
| VoiceOver                         | Not yet claimable | Complete common-task matrix, including HUD status announcements            |
| Voice Control                     | Not yet claimable | Operate onboarding, settings, purchase and restore without pointer         |
| Dark Interface                    | Candidate         | Native screenshots and contrast review for every settings page and overlay |
| Differentiate Without Color Alone | Candidate         | State/error audit for icons, labels and charts                             |
| Sufficient Contrast               | Candidate         | Automated and native enhanced-contrast verification                        |
| Reduced Motion                    | Candidate         | Onboarding, settings, HUD and landing fallbacks verified                   |

The Mac does not expose the Larger Text label in Apple's current matrix. Captions
and Audio Descriptions are not applicable unless the submitted product includes
instructional audio/video that makes them common tasks.

## Sources

- https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/
- https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/
