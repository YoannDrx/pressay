import { LoaderCircle } from "lucide-react";
import { useTranslation } from "react-i18next";

import { Button } from "@/components/ui/Button";
import type { ProUpgrade } from "@/hooks/useProUpgrade";

/**
 * While the web checkout is open: explains where to finish the purchase and
 * lets the user ask for an immediate entitlement check on return.
 */
export function ProUpgradeStatus({ upgrade }: { upgrade: ProUpgrade }) {
  const { t } = useTranslation();
  if (!upgrade.awaiting) return null;
  return (
    <div
      className="space-y-2 rounded-lg border border-accent/20 bg-accent/5 px-3 py-2 text-xs text-text"
      role="status"
      data-testid="pro-upgrade-status"
    >
      <div className="flex items-center justify-between gap-3">
        <span>{t("upgrade.waiting")}</span>
        <Button
          size="sm"
          variant="secondary"
          className="shrink-0"
          onClick={() => void upgrade.confirm()}
          disabled={upgrade.checking}
        >
          {upgrade.checking ? (
            <LoaderCircle className="mr-1.5 h-3.5 w-3.5 animate-spin" />
          ) : null}
          {t("upgrade.done")}
        </Button>
      </div>
      {upgrade.notYetActive ? (
        <p className="text-mid-gray">{t("upgrade.notYet")}</p>
      ) : null}
    </div>
  );
}
