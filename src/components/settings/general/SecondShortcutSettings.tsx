import React, { useState } from "react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { commands } from "@/bindings";
import { SettingContainer } from "../../ui/SettingContainer";
import { Dropdown } from "../../ui/Dropdown";
import { ShortcutInput } from "../ShortcutInput";
import { useSettings } from "../../../hooks/useSettings";
import {
  getLanguageLabel,
  SELECTABLE_LANGUAGES,
} from "../../../lib/constants/languages";

/** Id kept from the former post-processing shortcut (see settings.rs). */
export const SECOND_DICTATION_BINDING_ID = "transcribe_with_post_process";
const TRANSLATE_TO_MODE_ID = "translate_to";
/** Dropdown value for "follow the active mode and app profiles". */
const ACTIVE_MODE_VALUE = "__active__";

/**
 * The second dictation shortcut: its keys, the mode it always dictates with,
 * and — for "Dictate and translate" — the target language.
 */
export const SecondShortcutSettings: React.FC = () => {
  const { t } = useTranslation();
  const { getSetting, updateSetting, refreshSettings, isUpdating } =
    useSettings();
  const [savingMode, setSavingMode] = useState(false);

  const binding = getSetting("bindings")?.[SECOND_DICTATION_BINDING_ID];
  const modes = getSetting("pressay_modes") ?? [];
  const modeId = binding?.mode_id ?? null;
  const targetLanguage = getSetting("translation_target_language") ?? "en";

  const modeOptions = [
    {
      value: ACTIVE_MODE_VALUE,
      label: t("settings.general.secondShortcut.activeMode"),
    },
    ...modes.map((mode) => ({
      value: mode.id,
      label:
        mode.id === TRANSLATE_TO_MODE_ID
          ? t("settings.general.secondShortcut.translateMode")
          : mode.name,
    })),
  ];

  const languageOptions = SELECTABLE_LANGUAGES.filter(
    (language) => language.value !== "auto",
  ).map((language) => ({
    value: language.value,
    label: getLanguageLabel(language.value) ?? language.label,
  }));

  const changeMode = async (value: string) => {
    setSavingMode(true);
    try {
      const result = await commands.changeBindingMode(
        SECOND_DICTATION_BINDING_ID,
        value === ACTIVE_MODE_VALUE ? null : value,
      );
      if (result.status === "error") {
        toast.error(t("settings.general.secondShortcut.modeError"));
      }
      await refreshSettings();
    } finally {
      setSavingMode(false);
    }
  };

  return (
    <>
      <ShortcutInput
        shortcutId={SECOND_DICTATION_BINDING_ID}
        descriptionMode="tooltip"
        grouped={true}
      />
      <SettingContainer
        title={t("settings.general.secondShortcut.modeTitle")}
        description={t("settings.general.secondShortcut.modeDescription")}
        descriptionMode="tooltip"
        grouped={true}
      >
        <Dropdown
          options={modeOptions}
          selectedValue={modeId ?? ACTIVE_MODE_VALUE}
          onSelect={changeMode}
          disabled={savingMode}
        />
      </SettingContainer>
      {modeId === TRANSLATE_TO_MODE_ID && (
        <SettingContainer
          title={t("settings.general.secondShortcut.targetTitle")}
          description={t(
            targetLanguage === "en"
              ? "settings.general.secondShortcut.targetEnglish"
              : "settings.general.secondShortcut.targetOther",
          )}
          descriptionMode="inline"
          grouped={true}
        >
          <Dropdown
            options={languageOptions}
            selectedValue={targetLanguage}
            onSelect={(value) =>
              updateSetting("translation_target_language", value)
            }
            disabled={isUpdating("translation_target_language")}
          />
        </SettingContainer>
      )}
    </>
  );
};
