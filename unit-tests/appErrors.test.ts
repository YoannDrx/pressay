import { describe, expect, test } from "bun:test";
import english from "../src/i18n/locales/en/translation.json";
import french from "../src/i18n/locales/fr/translation.json";
import { appErrorKey, isUpgradeRequired } from "../src/lib/appErrors";

function lookup(catalogue: unknown, key: string): unknown {
  return key
    .split(".")
    .reduce<unknown>(
      (node, part) =>
        node && typeof node === "object"
          ? (node as Record<string, unknown>)[part]
          : undefined,
      catalogue,
    );
}

describe("backend error codes", () => {
  test("capability codes never reach the UI verbatim", () => {
    expect(appErrorKey("capability_upgrade_required:custom_modes")).toBe(
      "errors.codes.upgradeRequired",
    );
    expect(appErrorKey("capability_release_gate:direct_checkout")).toBe(
      "errors.codes.releaseGate",
    );
    expect(isUpgradeRequired("capability_upgrade_required:byok")).toBe(true);
    expect(isUpgradeRequired("cloud_network_unavailable")).toBe(false);
  });

  test("unknown or empty codes fall back to a generic message", () => {
    expect(appErrorKey("something_new")).toBe("errors.codes.generic");
    expect(appErrorKey(null)).toBe("errors.codes.generic");
  });

  test("every mapped key is translated in English and French", () => {
    const codes = [
      "cloud_network_unavailable",
      "cloud_unavailable",
      "cloud_rate_limited",
      "cloud_unauthorized",
      "cloud_not_connected",
      "cloud_keychain_unavailable",
      "cloud_browser_open_failed",
      "cloud_auth_state_mismatch",
      "cloud_auth_provider_failed",
      "cloud_account_mismatch",
      "apple_subscription_active",
      "storekit_pending",
      "storekit_unverified",
      "storekit_products_unavailable",
      "storekit_release_gate",
      "storekit_restore_failed",
      "storekit_account_invalid",
      "capability_upgrade_required:x",
      "capability_release_gate:x",
      "unknown",
    ];
    for (const code of codes) {
      const key = appErrorKey(code);
      expect(typeof lookup(english, key)).toBe("string");
      expect(typeof lookup(french, key)).toBe("string");
    }
  });
});

describe("presentError", () => {
  const t = (key: string) => `t:${key}`;
  test("translates codes and keeps readable messages", async () => {
    const { presentError } = await import("../src/lib/appErrors");
    expect(presentError(t, "capability_upgrade_required:custom_modes")).toBe(
      "t:errors.codes.upgradeRequired",
    );
    expect(presentError(t, "Mode name is required.")).toBe(
      "Mode name is required.",
    );
    expect(presentError(t, null)).toBe("");
  });
});
