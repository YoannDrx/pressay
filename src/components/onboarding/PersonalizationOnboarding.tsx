import { ArrowRight, SlidersHorizontal } from "lucide-react";
import { useTranslation } from "react-i18next";
import { LanguageSelector } from "@/components/settings/LanguageSelector";
import { MicrophoneSelector } from "@/components/settings/MicrophoneSelector";
import { ShowOverlay } from "@/components/settings/ShowOverlay";
import PressayWordmark from "../icons/PressayWordmark";

export const PersonalizationOnboarding = ({
  onComplete,
}: {
  onComplete: () => void;
}) => {
  const { t } = useTranslation();

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
