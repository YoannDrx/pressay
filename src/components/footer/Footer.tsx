import React, { useState, useEffect } from "react";
import { getVersion } from "@tauri-apps/api/app";

import ModelSelector from "../model-selector";
import UpdateChecker from "../update-checker";
import { useDistribution } from "@/hooks/useDistribution";

const Footer: React.FC = () => {
  const [version, setVersion] = useState("");
  const { updaterAvailable } = useDistribution();

  useEffect(() => {
    const fetchVersion = async () => {
      try {
        const appVersion = await getVersion();
        setVersion(appVersion);
      } catch (error) {
        // Fall back to the build-time source version, never a literal.
        console.error("Failed to get app version:", error);
        setVersion(__APP_VERSION__);
      }
    };

    fetchVersion();
  }, []);

  return (
    <div className="w-full border-t border-mid-gray/20 pt-3">
      <div className="flex justify-between items-center text-xs px-4 pb-3 text-text/60">
        <div className="flex items-center gap-4">
          <ModelSelector />
        </div>

        {/* Update Status */}
        <div className="flex items-center gap-1">
          {/* App Store builds are updated by the App Store only (2.4.5). */}
          {updaterAvailable ? <UpdateChecker /> : null}
          {version ? (
            <>
              {updaterAvailable ? <span>•</span> : null}
              {/* eslint-disable-next-line i18next/no-literal-string */}
              <span>v{version}</span>
            </>
          ) : null}
        </div>
      </div>
    </div>
  );
};

export default Footer;
