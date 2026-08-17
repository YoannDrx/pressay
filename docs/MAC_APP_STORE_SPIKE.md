# Mac App Store feasibility spike

## Current result

The sandboxed `app.pressay.desktop.mas` variant now compiles with a dedicated
`mas` feature and a public Tauri window for the recording overlay. Its Cargo
dependency graph excludes both `tauri-nspanel` and `macos-private-api`; CI
enforces that boundary. Direct releases retain the native NSPanel overlay behind
the separate `direct` feature, which is enabled by the `updater` release feature.

This clears the private-API build blocker, but it does not make the Store build
submission-ready. The remaining sandbox capabilities still require hands-on
validation with an Apple development profile, StoreKit sandbox products, and a
TestFlight upload.

The spike is complete only when a sandboxed Apple Silicon build demonstrates:

- microphone capture;
- global shortcut registration and Fn behavior;
- Accessibility permission detection;
- reliable paste into a different process;
- selected-text access without clipboard leakage;
- a public-API recording overlay (compile gate complete; runtime test pending);
- menu-bar operation and login item behavior;
- model download inside the app container;
- macOS Keychain access;
- outbound Pressay Cloud traffic;
- StoreKit purchase and restore in sandbox;
- archive, validation, and TestFlight upload.

The Store build must not contain `macos-private-api`, the updater capability, an
external checkout action, or a non-sandbox file scope. Any failed capability is
recorded with a reproducible test and does not block the direct DMG release.
