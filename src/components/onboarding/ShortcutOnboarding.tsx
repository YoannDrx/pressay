import { useEffect, useState } from "react";
import { ArrowRight, Check, Command, Mic2, Radio } from "lucide-react";
import { useTranslation } from "react-i18next";
import { commands, events } from "@/bindings";
import { ShortcutInput } from "@/components/settings/ShortcutInput";
import PressayWordmark from "../icons/PressayWordmark";

export const ShortcutOnboarding = ({
  onComplete,
}: {
  onComplete: () => void;
}) => {
  const { t } = useTranslation();
  const gesture = [
    t("signalOs.onboarding.shortcut.gesture.hold"),
    t("signalOs.onboarding.shortcut.gesture.speak"),
    t("signalOs.onboarding.shortcut.gesture.release"),
  ];
  const [tested, setTested] = useState(false);
  const [gestureStep, setGestureStep] = useState(0);

  useEffect(() => {
    // Register the configured global shortcut for the rehearsal. Keyboard
    // insertion stays uninitialised until the real sandbox step.
    void commands.initializeShortcuts();
    const unlisten = events.voiceSurfaceState.listen((event) => {
      if (["arming", "listening"].includes(event.payload.phase)) {
        setGestureStep((step) => Math.max(step, 1));
      }
      if (event.payload.phase === "listening") {
        setGestureStep((step) => Math.max(step, 2));
      }
      if (["captured", "transcribing"].includes(event.payload.phase)) {
        setGestureStep(3);
        setTested(true);
        void commands.cancelOperation();
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
          <p className="product-eyebrow">
            {t("signalOs.onboarding.shortcut.eyebrow")}
          </p>
          <h1>{t("signalOs.onboarding.shortcut.title")}</h1>
          <p>{t("signalOs.onboarding.shortcut.description")}</p>
        </div>

        <div className="shortcut-setup-card">
          <div className="shortcut-setup-label">
            <Command size={18} />
            <span>{t("signalOs.onboarding.shortcut.label")}</span>
          </div>
          <ShortcutInput shortcutId="transcribe" grouped />
          <ol className="gesture-rehearsal">
            {gesture.map((label, index) => {
              const complete = gestureStep > index;
              const Icon = index === 0 ? Command : index === 1 ? Mic2 : Radio;
              return (
                <li
                  key={label}
                  className={complete ? "is-complete" : undefined}
                >
                  <span>
                    {complete ? <Check size={13} /> : <Icon size={13} />}
                  </span>
                  {label}
                </li>
              );
            })}
          </ol>
          <div className={`shortcut-test-status ${tested ? "is-tested" : ""}`}>
            <Check size={16} />
            <span>
              {tested
                ? t("signalOs.onboarding.shortcut.tested")
                : t("signalOs.onboarding.shortcut.test")}
            </span>
          </div>
        </div>

        <button
          type="button"
          className="onboarding-primary"
          onClick={onComplete}
        >
          {tested
            ? t("signalOs.onboarding.shortcut.continue")
            : t("signalOs.onboarding.shortcut.skip")}
          <ArrowRight size={16} />
        </button>
      </div>
    </div>
  );
};
