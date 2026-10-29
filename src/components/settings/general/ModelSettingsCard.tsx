import React from "react";
import { useTranslation } from "react-i18next";
import { SettingsGroup } from "../../ui/SettingsGroup";
import { SettingContainer } from "../../ui/SettingContainer";
import { LanguageSelector } from "../LanguageSelector";
import { TranslateToEnglish } from "../TranslateToEnglish";
import { useModelStore } from "../../../stores/modelStore";
import type { ModelInfo } from "@/bindings";
import {
  CHINESE_LANGUAGE_CODE,
  getUniqueCapabilityLanguages,
} from "@/lib/constants/languages";

export const ModelSettingsCard: React.FC = () => {
  const { t } = useTranslation();
  const { currentModel, models } = useModelStore();

  const currentModelInfo = models.find((m: ModelInfo) => m.id === currentModel);

  const supportsLanguageSelection =
    currentModelInfo?.supports_language_selection ?? false;
  const capabilityLanguages = getUniqueCapabilityLanguages(
    currentModelInfo?.supported_languages ?? [],
  );
  const supportsChineseOnlyScriptSelection =
    capabilityLanguages.length === 1 &&
    capabilityLanguages[0] === CHINESE_LANGUAGE_CODE;
  const showLanguageSelector =
    supportsLanguageSelection || supportsChineseOnlyScriptSelection;
  // Parakeet V3 re-detects the language on every utterance: a picker here
  // would promise a choice the engine never receives.
  const ignoresLanguageHint = currentModelInfo?.honors_language_hint === false;
  const supportsTranslation = currentModelInfo?.supports_translation ?? false;
  const hasAnySettings = showLanguageSelector || supportsTranslation;

  // Don't render anything if no model is selected or no settings available
  if (!currentModel || !currentModelInfo || !hasAnySettings) {
    return null;
  }

  return (
    <SettingsGroup
      title={t("settings.modelSettings.title", {
        model: currentModelInfo.name,
      })}
    >
      {showLanguageSelector && ignoresLanguageHint && (
        <SettingContainer
          title={t("settings.general.language.title")}
          description={t("settings.general.language.autoDetectOnly")}
          descriptionMode="inline"
          grouped={true}
        >
          <span className="text-sm text-mid-gray">
            {t("settings.general.language.auto")}
          </span>
        </SettingContainer>
      )}
      {showLanguageSelector && !ignoresLanguageHint && (
        <LanguageSelector
          descriptionMode="tooltip"
          grouped={true}
          supportedLanguages={currentModelInfo.supported_languages}
          supportsLanguageDetection={
            currentModelInfo.supports_language_detection
          }
        />
      )}
      {supportsTranslation && (
        <TranslateToEnglish descriptionMode="tooltip" grouped={true} />
      )}
    </SettingsGroup>
  );
};
