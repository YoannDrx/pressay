import React from "react";
import { createRoot } from "react-dom/client";
import { mockIPC } from "@tauri-apps/api/mocks";
import { ProGate } from "../../src/components/shared/ProGate";
import { APP_NAVIGATE_EVENT } from "../../src/lib/appNavigation";
import type { Capabilities } from "../../src/bindings";
import "../../src/i18n";
import "../../src/App.css";

// Exercise the production gate with the capability matrix each build would
// report. `store` is the Mac App Store build: its direct checkout is compiled
// closed, so it must never offer the web purchase.
const params = new URLSearchParams(location.search);
const build = params.get("build");
const signedOut = params.get("account") === "signed-out";
const paidOnReturn = params.get("paid") === "yes";
let checkoutOpened = false;
const calls: string[] = [];
const payloads: Record<string, unknown>[] = [];
const navigations: string[] = [];
Object.assign(window, {
  gateTestCalls: calls,
  gateTestPayloads: payloads,
  gateTestNavigations: navigations,
});
window.addEventListener(APP_NAVIGATE_EVENT, (event) =>
  navigations.push((event as CustomEvent<string>).detail),
);

const capabilities = (): Capabilities => {
  const pro = paidOnReturn && checkoutOpened;
  const locked = pro ? "enabled" : "upgrade_required";
  return {
    entitlementsEnforced: true,
    tier: pro ? "pro" : "free",
    entitlementSource: pro ? "stripe" : "none",
    entitlementState: signedOut ? "local_free" : "verified",
    entitlementError: null,
    localDictation: "enabled",
    localHistory: "enabled",
    basicDictionary: "enabled",
    deterministicVoiceCommands: "enabled",
    customModes: locked,
    appProfiles: locked,
    voiceCorrection: locked,
    byok: locked,
    appleIntelligence: locked,
    encryptedSync: locked,
    pressayCloud: locked,
    directCheckout: build === "direct" ? "enabled" : "release_gate",
    appStorePurchase: build === "store" ? "enabled" : "release_gate",
  };
};

mockIPC((command, payload) => {
  calls.push(command);
  switch (command) {
    case "get_capabilities":
      return capabilities();
    case "open_external_page":
      payloads.push({ command, ...(payload as Record<string, unknown>) });
      checkoutOpened = true;
      return null;
    default:
      throw new Error(`Unexpected test IPC command: ${command}`);
  }
});

createRoot(document.getElementById("root")!).render(
  <ProGate capability="byok" />,
);
