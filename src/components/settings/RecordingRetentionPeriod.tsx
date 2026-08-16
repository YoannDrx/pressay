import React from "react";
import { useTranslation } from "react-i18next";
import { HistoryRetentionPeriod } from "@/bindings";
import { useSettings } from "../../hooks/useSettings";
import { Dropdown } from "../ui/Dropdown";
import { SettingContainer } from "../ui/SettingContainer";

interface RecordingRetentionPeriodProps {
  descriptionMode?: "inline" | "tooltip";
  grouped?: boolean;
}

export const RecordingRetentionPeriodSelector: React.FC<RecordingRetentionPeriodProps> =
  React.memo(({ descriptionMode = "tooltip", grouped = false }) => {
    const { t } = useTranslation();
    const { getSetting, updateSetting, isUpdating } = useSettings();
    const enabled = getSetting("history_enabled") ?? false;

    const options = [
      {
        value: "hours24",
        label: t("settings.historyPolicy.hours24", {
          defaultValue: "After 24 hours",
        }),
      },
      {
        value: "days7",
        label: t("settings.historyPolicy.days7", {
          defaultValue: "After 7 days",
        }),
      },
      {
        value: "days30",
        label: t("settings.historyPolicy.days30", {
          defaultValue: "After 30 days",
        }),
      },
      {
        value: "forever",
        label: t("settings.historyPolicy.forever", {
          defaultValue: "Never delete automatically",
        }),
      },
    ];

    const retentionSelector = (
      setting: "history_text_retention" | "history_audio_retention",
      title: string,
      description: string,
    ) => (
      <SettingContainer
        title={title}
        description={description}
        descriptionMode={descriptionMode}
        grouped={grouped}
      >
        <Dropdown
          options={options}
          selectedValue={getSetting(setting) ?? "forever"}
          onSelect={(period) =>
            updateSetting(setting, period as HistoryRetentionPeriod)
          }
          placeholder={t("settings.historyPolicy.placeholder", {
            defaultValue: "Select a retention period",
          })}
          disabled={!enabled || isUpdating(setting)}
        />
      </SettingContainer>
    );

    return (
      <>
        {retentionSelector(
          "history_text_retention",
          t("settings.historyPolicy.textTitle", {
            defaultValue: "Text retention",
          }),
          t("settings.historyPolicy.textDescription", {
            defaultValue:
              "Saved favorites are exempt from automatic text deletion.",
          }),
        )}
        {retentionSelector(
          "history_audio_retention",
          t("settings.historyPolicy.audioTitle", {
            defaultValue: "Audio retention",
          }),
          t("settings.historyPolicy.audioDescription", {
            defaultValue:
              "Audio expires independently, including for text favorites unless explicitly preserved.",
          }),
        )}
      </>
    );
  });

RecordingRetentionPeriodSelector.displayName =
  "RecordingRetentionPeriodSelector";
