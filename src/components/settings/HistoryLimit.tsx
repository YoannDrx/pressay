import React from "react";
import { useTranslation } from "react-i18next";
import { useSettings } from "../../hooks/useSettings";
import { ToggleSwitch } from "../ui/ToggleSwitch";

interface HistoryLimitProps {
  descriptionMode?: "tooltip" | "inline";
  grouped?: boolean;
}

export const HistoryLimit: React.FC<HistoryLimitProps> = ({
  descriptionMode = "inline",
  grouped = false,
}) => {
  const { t } = useTranslation();
  const { getSetting, updateSetting, isUpdating } = useSettings();
  const enabled = getSetting("history_enabled") ?? false;

  return (
    <ToggleSwitch
      checked={enabled}
      onChange={(value) => updateSetting("history_enabled", value)}
      isUpdating={isUpdating("history_enabled")}
      label={t("settings.historyPolicy.enabled", {
        defaultValue: "Local history",
      })}
      description={t("settings.historyPolicy.enabledDescription", {
        defaultValue:
          "Off by default. When enabled, text and audio are encrypted on this Mac.",
      })}
      descriptionMode={descriptionMode}
      grouped={grouped}
    />
  );
};
