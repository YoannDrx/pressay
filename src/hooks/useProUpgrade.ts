import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";

import { commands } from "@/bindings";
import { describeAppError } from "@/lib/appErrors";

/**
 * The Direct (DMG, Windows) upgrade path. Pro is sold on the web pricing page
 * and granted by a signed Stripe webhook; the app only opens that page and
 * reads its entitlement again when the user comes back (window focus, handled
 * by the caller's refresh, or the explicit "finished" button).
 *
 * Only reachable when `capabilities.directCheckout` is enabled, which the
 * Mac App Store build can never compile (App Review 3.1.1).
 */
export function useProUpgrade({
  isPro,
  refresh,
}: {
  isPro: boolean;
  refresh: () => Promise<unknown>;
}) {
  const { t } = useTranslation();
  const [awaiting, setAwaiting] = useState(false);
  const [checking, setChecking] = useState(false);
  const [checked, setChecked] = useState(false);

  const start = useCallback(async () => {
    const result = await commands.openExternalPage("direct_checkout");
    if (result.status === "error") {
      toast.error(describeAppError(t, result.error));
      return;
    }
    setChecked(false);
    setAwaiting(true);
  }, [t]);

  const confirm = useCallback(async () => {
    setChecking(true);
    try {
      await refresh();
    } finally {
      setChecking(false);
      setChecked(true);
    }
  }, [refresh]);

  useEffect(() => {
    if (awaiting && isPro) {
      setAwaiting(false);
      setChecked(false);
      toast.success(t("cloud.appStore.purchased"));
    }
  }, [awaiting, isPro, t]);

  return {
    awaiting: awaiting && !isPro,
    checking,
    /** Shown after an explicit check that still found no Pro entitlement. */
    notYetActive: awaiting && checked && !checking && !isPro,
    start,
    confirm,
  };
}

export type ProUpgrade = ReturnType<typeof useProUpgrade>;
