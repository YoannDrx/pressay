import { useEffect, useRef, useState } from "react";
import { ArrowRight, CheckCircle2, Keyboard, ShieldCheck } from "lucide-react";
import { useTranslation } from "react-i18next";
import { commands, events, type VoiceSurfaceState } from "@/bindings";
import { useOsType } from "@/hooks/useOsType";
import { useSettings } from "@/hooks/useSettings";
import { formatKeyCombination } from "@/lib/utils/keyboard";
import { INITIAL_VOICE_SURFACE_STATE } from "@/lib/voiceSurface";
import PressayMark from "../icons/PressayMark";

export const FirstDictationOnboarding = ({
  onComplete,
  onSkip,
}: {
  onComplete: () => void;
  onSkip: () => void;
}) => {
  const { t } = useTranslation();
  const osType = useOsType();
  const { settings } = useSettings();
  const [surface, setSurface] = useState<VoiceSurfaceState>(
    INITIAL_VOICE_SURFACE_STATE,
  );
  const [text, setText] = useState("");
  const [succeeded, setSucceeded] = useState(false);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const shortcut = formatKeyCombination(
    settings?.bindings?.transcribe?.current_binding ?? "option+space",
    osType,
  );

  useEffect(() => {
    void Promise.all([
      commands.initializeEnigo(),
      commands.initializeShortcuts(),
    ]).finally(() => inputRef.current?.focus());

    const unlisten = events.voiceSurfaceState.listen((event) => {
      setSurface(event.payload);
      if (event.payload.phase === "success") {
        // Text insertion is performed by the native paste pipeline. WebKit can
        // update the textarea without delivering React's synthetic `onChange`,
        // so pipeline success — rather than local component state — is the
        // authoritative completion signal for this exercise.
        setSucceeded(true);
        window.setTimeout(() => {
          if (inputRef.current?.value) setText(inputRef.current.value);
          inputRef.current?.focus();
        }, 0);
      }
    });
    return () => {
      unlisten.then((dispose) => dispose());
    };
  }, []);

  return (
    <div className="onboarding-screen">
      <div className="onboarding-panel sandbox-panel">
        <div className="onboarding-brand-lockup">
          <PressayMark size={34} />
          {/* Brand name is intentionally not translated. */}
          {/* eslint-disable-next-line i18next/no-literal-string */}
          <span>Pressay</span>
        </div>
        <div className="onboarding-heading">
          <p className="product-eyebrow">
            {t("signalOs.onboarding.firstDictation.eyebrow")}
          </p>
          <h1>{t("signalOs.onboarding.firstDictation.title")}</h1>
          <p>{t("signalOs.onboarding.firstDictation.description")}</p>
        </div>

        <div className={`sandbox-card ${succeeded ? "is-complete" : ""}`}>
          <textarea
            ref={inputRef}
            value={text}
            onChange={(event) => setText(event.target.value)}
            placeholder={t("signalOs.onboarding.firstDictation.placeholder")}
            aria-label={t("signalOs.onboarding.firstDictation.title")}
          />
          <div className="sandbox-status" aria-live="polite">
            {succeeded ? (
              <CheckCircle2 size={16} aria-hidden="true" />
            ) : (
              <Keyboard size={16} aria-hidden="true" />
            )}
            <span>
              {t(
                `signalOs.onboarding.firstDictation.status.${
                  succeeded ? "success" : surface.phase
                }`,
              )}
            </span>
            {!succeeded && surface.phase === "hidden" ? (
              <kbd className="sandbox-shortcut">{shortcut}</kbd>
            ) : null}
          </div>
        </div>

        <div className="sandbox-route">
          <ShieldCheck size={15} aria-hidden="true" />
          <strong>{t("signalOs.onboarding.firstDictation.route")}</strong>
          <span>{t("signalOs.onboarding.firstDictation.privacy")}</span>
        </div>

        <button
          type="button"
          className="onboarding-primary"
          disabled={!succeeded}
          onClick={onComplete}
        >
          {t("signalOs.onboarding.firstDictation.continue")}
          <ArrowRight size={16} aria-hidden="true" />
        </button>
        {!succeeded ? (
          <button
            type="button"
            className="onboarding-secondary"
            onClick={onSkip}
          >
            {t("signalOs.onboarding.firstDictation.skip")}
          </button>
        ) : null}
      </div>
    </div>
  );
};
