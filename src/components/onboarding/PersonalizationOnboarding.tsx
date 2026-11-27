import { useEffect } from "react";
import { ArrowRight, SlidersHorizontal } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useSettings } from "@/hooks/useSettings";
import { SELECTABLE_LANGUAGES } from "@/lib/constants/languages";
import { LanguageSelector } from "@/components/settings/LanguageSelector";
import { MicrophoneSelector } from "@/components/settings/MicrophoneSelector";
import { ShowOverlay } from "@/components/settings/ShowOverlay";
import PressayWordmark from "../icons/PressayWordmark";

export const PersonalizationOnboarding = ({
  onComplete,
}: {
  onComplete: () => void;
}) => {
  const { t, i18n } = useTranslation();
  const { getSetting, updateSetting } = useSettings();
  const spokenLanguage = getSetting("selected_language");

  // Most people dictate in the language of their interface: start there so
  // Pressay keeps that language from the first dictation. "auto" stays one
  // click away for people who switch languages.
  useEffect(() => {
    if (spokenLanguage !== "auto") return;
    const interfaceLanguage = i18n.language.split("-")[0];
    if (SELECTABLE_LANGUAGES.some((l) => l.value === interfaceLanguage)) {
      updateSetting("selected_language", interfaceLanguage);
    }
  }, [spokenLanguage, i18n.language, updateSetting]);

  return (
    <div className="onboarding-screen">
      <div className="onboarding-panel personalization-panel">
        <PressayWordmark width={138} />
        <div className="onboarding-heading">
          <p className="product-eyebrow">
            {t("signalOs.onboarding.personalization.eyebrow")}
          </p>
          <h1>{t("signalOs.onboarding.personalization.title")}</h1>
          <p>{t("signalOs.onboarding.personalization.description")}</p>
        </div>
        <div className="personalization-card">
          <div className="personalization-card-title" aria-hidden="true">
            <SlidersHorizontal size={17} />
          </div>
          <MicrophoneSelector />
          <LanguageSelector />
          <ShowOverlay />
        </div>
        <button
          type="button"
          className="onboarding-primary"
          onClick={onComplete}
        >
          {t("signalOs.onboarding.personalization.continue")}
          <ArrowRight size={16} aria-hidden="true" />
        </button>
      </div>
    </div>
  );
};
