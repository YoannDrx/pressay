# Mac App Store feasibility spike

## Current result

The sandboxed `app.pressay.desktop.mas` bundle builds and carries the expected
App Sandbox entitlements. Submission remains blocked because the inherited
recording overlay still links `tauri-nspanel` / `macos-private-api`. The Store
workflow fails deliberately until that overlay is replaced with public APIs.

The spike is complete only when a sandboxed Apple Silicon build demonstrates:

- microphone capture;
- global shortcut registration and Fn behavior;
- Accessibility permission detection;
- reliable paste into a different process;
- selected-text access without clipboard leakage;
- a public-API recording overlay;
- menu-bar operation and login item behavior;
- model download inside the app container;
- macOS Keychain access;
- outbound Pressay Cloud traffic;
- StoreKit purchase and restore in sandbox;
- archive, validation, and TestFlight upload.

The Store build must not contain `macos-private-api`, the updater capability, an
external checkout action, or a non-sandbox file scope. Any failed capability is
recorded with a reproducible test and does not block the direct DMG release.
