import React from "react";
import ReactDOM from "react-dom/client";
import { isTauri } from "@tauri-apps/api/core";
import { platform } from "@tauri-apps/plugin-os";
import App from "./App";
import { ProductPreview } from "./components/preview/ProductPreview";
import { installCompatShims } from "./lib/compat";
import {
  applyTheme,
  getStoredTheme,
  syncThemeFromSettings,
} from "./lib/utils/theme";

installCompatShims();

const hasTauriRuntime = isTauri();

// Set platform before render so CSS can scope per-platform (e.g. scrollbar styles)
document.documentElement.dataset.platform = hasTauriRuntime
  ? platform()
  : "browser";

// Apply the last-known theme synchronously before render to avoid a flash of
// the wrong palette, then reconcile with the persisted setting once it loads.
applyTheme(getStoredTheme());
if (hasTauriRuntime) {
  syncThemeFromSettings();
}

// Initialize i18n
import "./i18n";

// Initialize model store (loads models and sets up event listeners)
import { useModelStore } from "./stores/modelStore";
if (hasTauriRuntime) {
  useModelStore.getState().initialize();
}

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    {hasTauriRuntime ? <App /> : <ProductPreview />}
  </React.StrictMode>,
);
