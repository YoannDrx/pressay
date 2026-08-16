# Security and privacy policy

Pressay handles microphone audio, transcribed text, selected text, clipboard
contents, authentication tokens, and third-party API credentials. Treat all of
these values as sensitive user content.

## Reporting

Do not open a public issue for a vulnerability or attach user content to a bug
report. Contact `security@press-say.app` with a minimal reproduction and no real
transcript or credential. This address must be operational before public beta.

## Logging rules

Logs and crash reports must never contain:

- transcript, prompt, selected text, or clipboard contents;
- raw or encoded audio;
- API keys, cookies, authorization headers, OAuth codes, or refresh tokens;
- encrypted payloads that could be replayed;
- full local paths when a category and basename are sufficient.

Allowed diagnostic fields include a random request ID, duration, byte/sample
count, state transition, model ID, error category, app version, OS version, and
hardware class.

## Release requirements

- Secret scanning and dependency review pass.
- The Tauri capability allowlist and CSP are reviewed.
- A diagnostic export is inspected manually for user content.
- Model licences and hashes are included in the release manifest.
- Cloud remains disabled until retention disclosures and provider agreements are
  accurate for the production account.
