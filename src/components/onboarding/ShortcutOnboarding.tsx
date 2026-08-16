import { useEffect, useState } from "react";
import { ArrowRight, CheckCircle2, Command } from "lucide-react";
import { useTranslation } from "react-i18next";
import { events } from "@/bindings";
import { ShortcutInput } from "@/components/settings/ShortcutInput";
import PressayWordmark from "../icons/PressayWordmark";

const COPY = {
  en: {
    eyebrow: "YOUR SHORTCUT",
    title: "Make dictation instinctive.",
    description:
      "Keep the default shortcut or choose your own. Press it once to test that Pressay receives it.",
    label: "Recording shortcut",
    test: "Waiting for a shortcut test",
    tested: "Shortcut detected",
    continue: "Choose a model",
    skip: "Continue without testing",
  },
  fr: {
    eyebrow: "VOTRE RACCOURCI",
    title: "Rendez la dictée instinctive.",
    description:
      "Gardez le raccourci par défaut ou choisissez le vôtre. Appuyez une fois dessus pour vérifier que Pressay le reçoit.",
    label: "Raccourci d’enregistrement",
    test: "En attente d’un test",
    tested: "Raccourci détecté",
    continue: "Choisir un modèle",
    skip: "Continuer sans tester",
  },
} as const;

export const ShortcutOnboarding = ({
  onComplete,
}: {
  onComplete: () => void;
}) => {
  const { i18n } = useTranslation();
  const copy = COPY[i18n.resolvedLanguage?.startsWith("fr") ? "fr" : "en"];
  const [tested, setTested] = useState(false);

  useEffect(() => {
    const unlisten = events.pipelineState.listen((event) => {
      if (event.payload.phase === "recording") {
        setTested(true);
      }
    });
    return () => {
      unlisten.then((dispose) => dispose());
    };
  }, []);

  return (
    <div className="onboarding-screen">
      <div className="onboarding-panel shortcut-panel">
        <PressayWordmark width={138} />
        <div className="onboarding-heading">
          <p className="product-eyebrow">{copy.eyebrow}</p>
          <h1>{copy.title}</h1>
          <p>{copy.description}</p>
        </div>

        <div className="shortcut-setup-card">
          <div className="shortcut-setup-label">
            <Command size={18} />
            <span>{copy.label}</span>
          </div>
          <ShortcutInput shortcutId="transcribe" grouped />
          <div className={`shortcut-test-status ${tested ? "is-tested" : ""}`}>
            <CheckCircle2 size={16} />
            <span>{tested ? copy.tested : copy.test}</span>
          </div>
        </div>

        <button
          type="button"
          className="onboarding-primary"
          onClick={onComplete}
        >
          {tested ? copy.continue : copy.skip}
          <ArrowRight size={16} />
        </button>
      </div>
    </div>
  );
};
