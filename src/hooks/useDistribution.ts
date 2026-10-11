import { useEffect, useState } from "react";
import { commands, type DistributionInfo } from "@/bindings";

// Until the native answer arrives, assume the most restrictive channel: no
// self-update UI and no external purchase surface.
const RESTRICTED: DistributionInfo = {
  channel: "mac_app_store",
  updaterAvailable: false,
};

let cached: DistributionInfo | null = null;
let pending: Promise<DistributionInfo> | null = null;

export function loadDistributionInfo(): Promise<DistributionInfo> {
  if (cached) return Promise.resolve(cached);
  pending ??= commands
    .getDistributionInfo()
    .then((info) => {
      cached = info;
      return info;
    })
    .catch(() => {
      pending = null;
      return RESTRICTED;
    });
  return pending;
}

/** The compile-time distribution channel of this binary. */
export function useDistribution(): DistributionInfo {
  const [info, setInfo] = useState<DistributionInfo>(cached ?? RESTRICTED);
  useEffect(() => {
    let active = true;
    void loadDistributionInfo().then((value) => {
      if (active) setInfo(value);
    });
    return () => {
      active = false;
    };
  }, []);
  return info;
}
