import { useCallback, useEffect, useState } from "react";
import { commands, type Capabilities } from "@/bindings";

/**
 * The backend capability matrix. `null` until loaded: callers must not lock a
 * feature before the native answer arrives (Free local features stay usable).
 */
export function useCapabilities(): {
  capabilities: Capabilities | null;
  refresh: () => Promise<void>;
} {
  const [capabilities, setCapabilities] = useState<Capabilities | null>(null);

  const refresh = useCallback(async () => {
    try {
      setCapabilities(await commands.getCapabilities());
    } catch (error) {
      console.warn("Failed to load capabilities:", error);
    }
  }, []);

  useEffect(() => {
    void refresh();
    const onFocus = () => void refresh();
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, [refresh]);

  return { capabilities, refresh };
}
