import { useEffect, useState } from "react";
import {
  AlertTriangle,
  ArrowRight,
  CheckCircle2,
  Cpu,
  HardDrive,
  Loader2,
  MemoryStick,
} from "lucide-react";
import { useTranslation } from "react-i18next";
import { commands, type LocalReadiness } from "@/bindings";
import PressayWordmark from "../icons/PressayWordmark";

const formatBytes = (value: number | null, fallback: string) => {
  if (value === null) return fallback;
  const gibibytes = value / 1024 ** 3;
  return `${gibibytes >= 10 ? Math.round(gibibytes) : gibibytes.toFixed(1)} GB`;
};

export const DiagnosticOnboarding = ({
  onComplete,
}: {
  onComplete: () => void;
}) => {
  const { t } = useTranslation();
  const [readiness, setReadiness] = useState<LocalReadiness | null>(null);
  const [failed, setFailed] = useState(false);

  const loadReadiness = () => {
    setFailed(false);
    commands
      .getLocalReadiness()
      .then(setReadiness)
      .catch(() => setFailed(true));
  };

  useEffect(loadReadiness, []);

  if (!readiness && !failed) {
    return (
      <div className="onboarding-screen">
        <Loader2 className="onboarding-loader" aria-hidden="true" />
      </div>
    );
  }

  if (!readiness) {
    return (
      <div className="onboarding-screen">
        <div className="onboarding-panel">
          <AlertTriangle className="onboarding-warning" aria-hidden="true" />
          <button
            type="button"
            className="onboarding-primary"
            onClick={loadReadiness}
          >
            {t("signalOs.onboarding.diagnostic.retry")}
          </button>
        </div>
      </div>
    );
  }

  const preset =
    readiness.recommended_preset === "precise"
      ? "precise"
      : readiness.recommended_preset === "polyglot"
        ? "polyglot"
        : "fast";
  const cards = [
    {
      label: t("signalOs.onboarding.diagnostic.chip"),
      value: readiness.chip || readiness.architecture,
      icon: Cpu,
    },
    {
      label: t("signalOs.onboarding.diagnostic.memory"),
      value: formatBytes(
        readiness.memory_bytes,
        t("signalOs.onboarding.diagnostic.unknown"),
      ),
      icon: MemoryStick,
    },
    {
      label: t("signalOs.onboarding.diagnostic.storage"),
      value: formatBytes(
        readiness.available_storage_bytes,
        t("signalOs.onboarding.diagnostic.unknown"),
      ),
      icon: HardDrive,
    },
    {
      label: t("signalOs.onboarding.diagnostic.system"),
      value:
        readiness.macos_version || t("signalOs.onboarding.diagnostic.unknown"),
      icon: CheckCircle2,
    },
  ];

  return (
    <div className="onboarding-screen">
      <div className="onboarding-panel diagnostic-panel">
        <PressayWordmark width={138} />
        <div className="onboarding-heading">
          <p className="product-eyebrow">
            {t("signalOs.onboarding.diagnostic.eyebrow")}
          </p>
          <h1>{t("signalOs.onboarding.diagnostic.title")}</h1>
          <p>{t("signalOs.onboarding.diagnostic.description")}</p>
        </div>

        <div className="diagnostic-grid">
          {cards.map(({ label, value, icon: Icon }) => (
            <article key={label} className="diagnostic-card">
              <Icon size={17} aria-hidden="true" />
              <span>{label}</span>
              <strong>{value}</strong>
            </article>
          ))}
        </div>

        <div
          className={`diagnostic-result ${readiness.supported ? "is-ready" : "is-limited"}`}
        >
          {readiness.supported ? (
            <CheckCircle2 size={18} aria-hidden="true" />
          ) : (
            <AlertTriangle size={18} aria-hidden="true" />
          )}
          <div>
            <strong>
              {readiness.supported
                ? t("signalOs.onboarding.diagnostic.supported")
                : t("signalOs.onboarding.diagnostic.limited")}
            </strong>
            <span>{t("signalOs.onboarding.diagnostic.recommendation")}</span>
            <p>{t(`signalOs.onboarding.diagnostic.presets.${preset}`)}</p>
          </div>
        </div>

        <button
          type="button"
          className="onboarding-primary"
          onClick={onComplete}
        >
          {t("signalOs.onboarding.diagnostic.continue")}
          <ArrowRight size={16} aria-hidden="true" />
        </button>
      </div>
    </div>
  );
};
