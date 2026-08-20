import { ArrowRight, Check, CloudOff, Sparkles } from "lucide-react";
import { useTranslation } from "react-i18next";
import PressayWordmark from "../icons/PressayWordmark";

export const ProDiscoveryOnboarding = ({
  onComplete,
}: {
  onComplete: () => void;
}) => {
  const { t } = useTranslation();
  const freeItems = [1, 2, 3].map((item) =>
    t(`signalOs.onboarding.pro.freeItems.${item}`),
  );
  const proItems = [1, 2, 3].map((item) =>
    t(`signalOs.onboarding.pro.proItems.${item}`),
  );

  return (
    <div className="onboarding-screen">
      <div className="onboarding-panel pro-discovery-panel">
        <PressayWordmark width={138} />
        <div className="onboarding-heading">
          <p className="product-eyebrow">
            {t("signalOs.onboarding.pro.eyebrow")}
          </p>
          <h1>{t("signalOs.onboarding.pro.title")}</h1>
          <p>{t("signalOs.onboarding.pro.description")}</p>
        </div>
        <div className="pro-discovery-grid">
          <article>
            <CloudOff aria-hidden="true" />
            <h2>{t("signalOs.onboarding.pro.free")}</h2>
            <ul>
              {freeItems.map((item) => (
                <li key={item}>
                  <Check size={14} aria-hidden="true" />
                  {item}
                </li>
              ))}
            </ul>
          </article>
          <article className="is-pro">
            <Sparkles aria-hidden="true" />
            <h2>{t("signalOs.onboarding.pro.pro")}</h2>
            <ul>
              {proItems.map((item) => (
                <li key={item}>
                  <Check size={14} aria-hidden="true" />
                  {item}
                </li>
              ))}
            </ul>
          </article>
        </div>
        <button
          type="button"
          className="onboarding-primary"
          onClick={onComplete}
        >
          {t("signalOs.onboarding.pro.finish")}
          <ArrowRight size={16} aria-hidden="true" />
        </button>
        <p className="onboarding-footnote">
          {t("signalOs.onboarding.pro.later")}
        </p>
      </div>
    </div>
  );
};
