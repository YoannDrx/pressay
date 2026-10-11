import { LockKeyhole } from "lucide-react";
import { useTranslation } from "react-i18next";

import type { Capabilities, CapabilityAccess } from "@/bindings";
import { Button } from "@/components/ui/Button";
import { useCapabilities } from "@/hooks/useCapabilities";
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
 * single path to the Account page (in-app purchase on the App Store build,
 * web checkout on Direct when that release gate is open). Renders nothing
 * while entitlements are not enforced or the feature is available.
 */
export function ProGate({ capability }: { capability: GatedCapability }) {
  const { t } = useTranslation();
  const { capabilities } = useCapabilities();
  if (!isLocked(capabilities, capability)) return null;
  const upgradable = capabilities?.[capability] === "upgrade_required";
  return (
    <div
      className="flex items-center justify-between gap-3 rounded-lg border border-accent/20 bg-accent/5 p-3"
      role="note"
    >
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
              {t("proGate.description")}
            </p>
          ) : null}
        </div>
      </div>
      {upgradable ? (
        <Button
          size="sm"
          variant="secondary"
          onClick={() => navigateToAppSection("account")}
        >
          {t("proGate.cta")}
        </Button>
      ) : null}
    </div>
  );
}
