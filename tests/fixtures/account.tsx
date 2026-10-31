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
const params = new URLSearchParams(location.search);
const scenario = params.get("scenario");
// The native confirmation answer; destructive commands must follow it.
const dialogAnswer = params.get("dialog") === "yes";
const signedOut = scenario === "signed-out";
const account: CloudAccountSnapshot = {
  connected: !signedOut,
  accountId: "00000000-0000-4000-8000-000000000001",
  deviceId: "00000000-0000-4000-8000-000000000002",
  email: "synthetic@example.invalid",
  entitlement: null,
  usage: null,
};
// The web checkout grants Pro through a webhook; this scenario simulates it
// having landed by the time the user comes back from the browser.
const proAfterCheckout = scenario === "direct-checkout-paid";
let checkoutOpened = false;
const proAccount: CloudAccountSnapshot = {
  ...account,
  entitlement: {
    tier: "pro",
    source: "stripe",
    validFrom: "2026-01-01T00:00:00Z",
    validUntil: null,
    offlineGraceUntil: null,
    revision: 2,
  },
};
const calls: string[] = [];
// Arguments of the commands whose payload matters to the assertions.
const payloads: Record<string, unknown>[] = [];
Object.assign(window, {
  accountTestCalls: calls,
  accountTestPayloads: payloads,
});
mockIPC(
  (command, payload) => {
    calls.push(command);
    if (
      [
        "open_external_page",
        "begin_cloud_social_login",
        "delete_cloud_account",
        "restore_app_store_purchases",
      ].includes(command)
    )
      payloads.push({ command, ...(payload as Record<string, unknown>) });
    switch (command) {
      case "get_capabilities":
        return {
          appStorePurchase: scenario?.startsWith("purchases-enabled")
            ? "enabled"
            : "release_gate",
          directCheckout: scenario?.startsWith("direct-checkout")
            ? "enabled"
            : "release_gate",
        };
      case "get_cloud_auth_config":
        return {
          providers: ["apple", "google"],
          callbackUrl: "pressay://oauth/callback",
        };
      case "get_cloud_account_snapshot":
        if (signedOut) return Promise.reject("cloud_not_connected");
        return proAfterCheckout && checkoutOpened ? proAccount : account;
      case "reconcile_app_store_purchases":
        return account;
      case "restore_app_store_purchases":
        // A purchase made under another Apple ID needs a confirmed link.
        if (
          scenario === "purchases-link" &&
          !(payload as { linkToCurrentAccount?: boolean }).linkToCurrentAccount
        )
          return Promise.reject("app_store_account_mismatch");
        return account;
      case "purchase_app_store_product":
        return Promise.reject("storekit_pending");
      case "open_external_page":
        if ((payload as { page?: string }).page === "direct_checkout")
          checkoutOpened = true;
        return null;
      case "begin_cloud_social_login":
      case "cancel_cloud_social_login":
        return null;
      case "get_cloud_sync_snapshot":
        return { status: "not_configured", devices: [] };
      case "plugin:dialog|ask":
        return dialogAnswer;
      case "delete_cloud_account":
        // The Cloud refuses while an App Store subscription is active, unless
        // the user acknowledged it (contract §3).
        if (
          scenario === "apple-subscription" &&
          !(payload as { acknowledgeAppleSubscription?: boolean })
            .acknowledgeAppleSubscription
        )
          return Promise.reject("apple_subscription_active");
        return null;
      case "get_app_store_products":
        if (
          [
            "direct",
            "direct-checkout",
            "direct-checkout-paid",
            "apple-subscription",
          ].includes(scenario ?? "")
        )
          return Promise.reject("storekit_distribution_unavailable");
        if (scenario === "offline")
          return Promise.reject("storekit_products_unavailable");
        if (scenario?.startsWith("purchases-"))
          return [
            {
              id: "app.pressay.desktop.mas.pro.monthly",
              displayName: "Pressay Pro",
              description: "Monthly",
              displayPrice: "€5",
              subscriptionPeriodUnit: "month",
              subscriptionPeriodValue: 1,
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
