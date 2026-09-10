import React from "react";
import { createRoot } from "react-dom/client";
import { mockIPC } from "@tauri-apps/api/mocks";
import { AccountSettings } from "../../src/components/settings/account/AccountSettings";
import { useSettingsStore } from "../../src/stores/settingsStore";
import type { CloudAccountSnapshot } from "../../src/bindings";
import "../../src/i18n";
import "../../src/App.css";

// Exercise the production component and generated IPC bindings. No live
// Keychain, Cloud account or StoreKit purchase is used by this fixture.
const scenario = new URLSearchParams(location.search).get("scenario");
const account: CloudAccountSnapshot = {
  connected: true,
  accountId: "00000000-0000-4000-8000-000000000001",
  deviceId: "00000000-0000-4000-8000-000000000002",
  email: "synthetic@example.invalid",
  entitlement: null,
  usage: null,
};
const calls: string[] = [];
Object.assign(window, { accountTestCalls: calls });
mockIPC(
  (command) => {
    calls.push(command);
    switch (command) {
      case "get_capabilities":
        return {
          appStorePurchase:
            scenario === "purchases-enabled" ? "enabled" : "release_gate",
        };
      case "get_cloud_auth_config":
        return {
          magicLink: false,
          providers: [],
          callbackUrl: "pressay://oauth/callback",
        };
      case "get_cloud_account_snapshot":
      case "reconcile_app_store_purchases":
      case "restore_app_store_purchases":
        return account;
      case "get_cloud_sync_snapshot":
        return { status: "not_configured", devices: [] };
      case "get_app_store_products":
        if (scenario === "direct")
          return Promise.reject("storekit_distribution_unavailable");
        if (scenario === "offline")
          return Promise.reject("storekit_products_unavailable");
        if (scenario === "purchases-enabled" || scenario === "purchases-gated")
          return [
            {
              id: "app.pressay.desktop.mas.pro.monthly",
              displayName: "Pressay Pro",
              description: "Monthly",
              displayPrice: "€5",
            },
          ];
        return [];
      default:
        throw new Error(`Unexpected test IPC command: ${command}`);
    }
  },
  { shouldMockEvents: true },
);
useSettingsStore.setState({ isLoading: false });
createRoot(document.getElementById("root")!).render(<AccountSettings />);
