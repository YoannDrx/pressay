/**
 * Map backend error codes (cloud_*, storekit_*, capability_*) to translated,
 * user-facing messages. Raw codes are never shown in the UI: they are
 * meaningless to users and App Review treats them as broken UI (2.1).
 */

type Translate = (key: string) => string;

const EXACT: Record<string, string> = {
  cloud_network_unavailable: "errors.codes.network",
  cloud_unavailable: "errors.codes.serviceUnavailable",
  cloud_rate_limited: "errors.codes.rateLimited",
  cloud_unauthorized: "errors.codes.sessionExpired",
  cloud_session_expired: "errors.codes.sessionExpired",
  cloud_not_connected: "errors.codes.notConnected",
  cloud_account_required: "errors.codes.notConnected",
  cloud_keychain_unavailable: "errors.codes.keychain",
  cloud_browser_open_failed: "errors.codes.browser",
  cloud_auth_state_mismatch: "errors.codes.authExpired",
  cloud_auth_timeout: "errors.codes.authExpired",
  cloud_auth_provider_failed: "errors.codes.authCancelled",
  cloud_oauth_endpoint_invalid: "errors.codes.serviceUnavailable",
  cloud_account_mismatch: "errors.codes.accountMismatch",
  apple_subscription_active: "errors.codes.appleSubscriptionActive",
  storekit_pending: "errors.codes.purchasePending",
  storekit_unverified: "errors.codes.purchaseUnverified",
  storekit_products_unavailable: "errors.codes.storeUnavailable",
  storekit_unavailable: "errors.codes.storeUnavailable",
  storekit_window_unavailable: "errors.codes.storeUnavailable",
  storekit_release_gate: "errors.codes.releaseGate",
  storekit_restore_failed: "errors.codes.restoreFailed",
  storekit_account_invalid: "errors.codes.otherAccount",
  external_page_open_failed: "errors.codes.browser",
  direct_checkout_unavailable: "errors.codes.releaseGate",
};

const PREFIXES: [string, string][] = [
  ["capability_upgrade_required", "errors.codes.upgradeRequired"],
  ["capability_release_gate", "errors.codes.releaseGate"],
  // The restore endpoint rejects a transaction bound to another account.
  ["app_store_account_mismatch", "errors.codes.otherAccount"],
  ["app_store_account_token_missing", "errors.codes.otherAccount"],
  ["invalid_app_store_transaction", "errors.codes.purchaseUnverified"],
];

export function appErrorKey(code: string | null | undefined): string {
  if (!code) return "errors.codes.generic";
  const normalized = code.trim();
  const exact = EXACT[normalized];
  if (exact) return exact;
  for (const [prefix, key] of PREFIXES) {
    if (normalized.startsWith(prefix)) return key;
  }
  return "errors.codes.generic";
}

export function describeAppError(
  t: Translate,
  code: string | null | undefined,
): string {
  return t(appErrorKey(code));
}

/** True for `capability_upgrade_required:*` (a Free user hit a Pro feature). */
export function isUpgradeRequired(code: string | null | undefined): boolean {
  return Boolean(code?.startsWith("capability_upgrade_required"));
}

const CODE_PATTERN = /^[a-z][a-z0-9_]*(?::[a-z0-9_]+)?$/;

/**
 * For results that carry either a machine code or an already human-readable
 * message: translate codes, keep readable messages as they are.
 */
export function presentError(t: Translate, raw: string | null | undefined) {
  if (!raw) return "";
  return CODE_PATTERN.test(raw.trim()) ? describeAppError(t, raw) : raw;
}
