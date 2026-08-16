import { ArrowRight, Check, Cloud, Laptop } from "lucide-react";
import { useTranslation } from "react-i18next";
import PressayWordmark from "../icons/PressayWordmark";

const COPY = {
  en: {
    eyebrow: "WELCOME TO PRESSAY",
    title: "Your voice, without the trade-off.",
    description:
      "Start with private transcription on your Mac. No account, no Internet connection, no behavioural analytics.",
    localTitle: "Local",
    localBody: "Free · Offline · No account",
    recommended: "Recommended",
    cloudTitle: "Pressay Cloud",
    cloudBody: "Optional · Explicit · Pro",
    cloudNote: "Configure it later from your account.",
    continue: "Continue locally",
    footnote:
      "Pressay never switches a local workflow to Cloud without asking you.",
  },
  fr: {
    eyebrow: "BIENVENUE DANS PRESSAY",
    title: "Votre voix, sans compromis.",
    description:
      "Commencez avec une transcription privée sur votre Mac. Sans compte, sans Internet et sans analytics comportementales.",
    localTitle: "Local",
    localBody: "Gratuit · Hors ligne · Sans compte",
    recommended: "Recommandé",
    cloudTitle: "Pressay Cloud",
    cloudBody: "Optionnel · Explicite · Pro",
    cloudNote: "À configurer plus tard depuis votre compte.",
    continue: "Continuer en local",
    footnote:
      "Pressay ne bascule jamais un flux local vers le Cloud sans vous le demander.",
  },
} as const;

export const WelcomeOnboarding = ({
  onComplete,
}: {
  onComplete: () => void;
}) => {
  const { i18n } = useTranslation();
  const copy = COPY[i18n.resolvedLanguage?.startsWith("fr") ? "fr" : "en"];

  return (
    <div className="onboarding-screen">
      <div className="onboarding-panel welcome-panel">
        <PressayWordmark width={138} />
        <div className="onboarding-heading">
          <p className="product-eyebrow">{copy.eyebrow}</p>
          <h1>{copy.title}</h1>
          <p>{copy.description}</p>
        </div>

        <div className="onboarding-route-grid">
          <article className="onboarding-route-card is-selected">
            <div className="onboarding-route-icon">
              <Laptop size={21} />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2>{copy.localTitle}</h2>
                <span>{copy.recommended}</span>
              </div>
              <p>{copy.localBody}</p>
            </div>
            <Check size={18} className="route-check" />
          </article>

          <article className="onboarding-route-card" aria-disabled="true">
            <div className="onboarding-route-icon">
              <Cloud size={21} />
            </div>
            <div>
              <h2>{copy.cloudTitle}</h2>
              <p>{copy.cloudBody}</p>
              <small>{copy.cloudNote}</small>
            </div>
          </article>
        </div>

        <button
          type="button"
          className="onboarding-primary"
          onClick={onComplete}
        >
          {copy.continue}
          <ArrowRight size={16} />
        </button>
        <p className="onboarding-footnote">{copy.footnote}</p>
      </div>
    </div>
  );
};
