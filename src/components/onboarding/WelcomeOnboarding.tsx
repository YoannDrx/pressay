import { ArrowRight, Check, LockKeyhole, WifiOff } from "lucide-react";
import { useTranslation } from "react-i18next";
import PressayMark from "../icons/PressayMark";

export const WelcomeOnboarding = ({
  onComplete,
}: {
  onComplete: () => void;
}) => {
  const { t } = useTranslation();

  return (
    <div className="onboarding-screen">
      <div className="onboarding-panel welcome-panel">
        <div className="onboarding-hero-mark" aria-hidden="true">
          <span className="onboarding-orbit orbit-one" />
          <span className="onboarding-orbit orbit-two" />
          <PressayMark size={76} />
        </div>
        <div className="onboarding-heading">
          <p className="product-eyebrow">
            {t("signalOs.onboarding.welcome.eyebrow")}
          </p>
          <h1>{t("signalOs.onboarding.welcome.title")}</h1>
          <p>{t("signalOs.onboarding.welcome.description")}</p>
        </div>

        <div className="onboarding-trust-card">
          <div>
            <Check size={15} aria-hidden="true" />
            <strong>{t("signalOs.onboarding.welcome.localTitle")}</strong>
          </div>
          <div>
            <WifiOff size={15} aria-hidden="true" />
            <strong>{t("pressay.sidebar.status.offline")}</strong>
          </div>
          <div>
            <LockKeyhole size={15} aria-hidden="true" />
            <strong>{t("signalOs.onboarding.firstDictation.privacy")}</strong>
          </div>
        </div>

        <button
          type="button"
          className="onboarding-primary"
          onClick={onComplete}
        >
          {t("signalOs.onboarding.welcome.continue")}
          <ArrowRight size={16} />
        </button>
        <p className="onboarding-footnote">
          {t("signalOs.onboarding.welcome.footnote")}
        </p>
      </div>
    </div>
  );
};
