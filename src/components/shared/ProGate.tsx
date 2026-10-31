import { LockKeyhole } from "lucide-react";
import { useTranslation } from "react-i18next";

import type { Capabilities, CapabilityAccess } from "@/bindings";
import { Button } from "@/components/ui/Button";
import { ProUpgradeStatus } from "@/components/shared/ProUpgradeStatus";
import { useCapabilities } from "@/hooks/useCapabilities";
import { useProUpgrade } from "@/hooks/useProUpgrade";
import { navigateToAppSection } from "@/lib/appNavigation";

type GatedCapability = {
  [K in keyof Capabilities]: Capabilities[K] extends CapabilityAccess
    ? K
    : never;
}[keyof Capabilities];

/** Whether the backend will refuse this capability for the current account. */
export function isLocked(
  capabilities: Capabilities | null,
  capability: GatedCapability,
): boolean {
  return (
    capabilities !== null &&
    capabilities.entitlementsEnforced &&
    capabilities[capability] !== "enabled"
  );
}

/**
 * Consistent locked state for Pro features: a translated explanation and a
 * single upgrade path. Direct builds that sell through the web checkout open
 * the pricing page straight away for a signed-in account (and read the
 * entitlement again on return); every other build, the App Store one
 * included, sends the user to the Account page (in-app purchase on the App
 * Store build). Renders nothing while entitlements are not enforced or the
 * feature is available.
 */
export function ProGate({ capability }: { capability: GatedCapability }) {
  const { t } = useTranslation();
  const { capabilities, refresh } = useCapabilities();
  const upgrade = useProUpgrade({
    isPro: capabilities?.tier === "pro",
    refresh,
  });
  if (!isLocked(capabilities, capability)) return null;
  const upgradable = capabilities?.[capability] === "upgrade_required";
  const webCheckout = capabilities?.directCheckout === "enabled";
  // Without a connected account the purchase could not reach this app: the
  // Account page signs in first, then offers the same upgrade button.
  const signedIn = capabilities?.entitlementState === "verified";
  const upgradeNow = () => {
    if (webCheckout && signedIn) void upgrade.start();
    else navigateToAppSection("account");
  };
  return (
    <div
      className="space-y-3 rounded-lg border border-accent/20 bg-accent/5 p-3"
      role="note"
    >
      <div className="flex items-center justify-between gap-3">
        <div className="flex min-w-0 items-start gap-2">
          <LockKeyhole
            className="mt-0.5 h-4 w-4 shrink-0 text-accent"
            aria-hidden="true"
          />
          <div className="min-w-0">
            <p className="text-sm font-medium text-text">
              {upgradable
                ? t("errors.codes.upgradeRequired")
                : t("errors.codes.releaseGate")}
            </p>
            {upgradable ? (
              <p className="mt-0.5 text-xs text-mid-gray">
                {webCheckout
                  ? t("proGate.directDescription")
                  : t("proGate.description")}
              </p>
            ) : null}
          </div>
        </div>
        {upgradable ? (
          <Button
            size="sm"
            variant={webCheckout ? "primary" : "secondary"}
            className="shrink-0"
            onClick={upgradeNow}
            disabled={upgrade.checking}
          >
            {webCheckout ? t("upgrade.cta") : t("proGate.cta")}
          </Button>
        ) : null}
      </div>
      <ProUpgradeStatus upgrade={upgrade} />
    </div>
  );
}
