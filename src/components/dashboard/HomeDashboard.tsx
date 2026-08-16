import { useEffect, useMemo, useState } from "react";
import {
  CheckCircle2,
  CloudOff,
  Command,
  Mic2,
  ShieldCheck,
  Sparkles,
} from "lucide-react";
import { useTranslation } from "react-i18next";
import { commands, events, type PipelineState } from "@/bindings";
import { useSettings } from "@/hooks/useSettings";
import { useModelStore } from "@/stores/modelStore";

const INITIAL_PIPELINE_STATE: PipelineState = {
  phase: "idle",
  operation_id: 0,
  binding_id: null,
  failure: null,
};

const COPY = {
  en: {
    eyebrow: "LOCAL DICTATION",
    title: "Ready when you are.",
    subtitle: "Your voice is transcribed on this Mac by default.",
    local: "Local",
    private: "Private by default",
    status: {
      idle: "Ready",
      recording: "Listening",
      transcribing: "Transcribing",
      transforming: "Transforming",
      pasting: "Inserting",
      cancelled: "Cancelled",
      failed: "Action needed",
    },
    model: "Model",
    microphone: "Microphone",
    shortcut: "Shortcut",
    defaultMicrophone: "System default",
    noModel: "Choose a model",
    privacyTitle: "Nothing leaves your Mac",
    privacyBody:
      "Local dictation works offline and without an account. Cloud processing is never selected silently.",
    mode: "Mode",
    faithful: "Faithful",
    route: "Processing route",
  },
  fr: {
    eyebrow: "DICTÉE LOCALE",
    title: "Prêt quand vous l’êtes.",
    subtitle: "Votre voix est transcrite sur ce Mac par défaut.",
    local: "Local",
    private: "Privé par défaut",
    status: {
      idle: "Prêt",
      recording: "Écoute en cours",
      transcribing: "Transcription",
      transforming: "Transformation",
      pasting: "Insertion",
      cancelled: "Annulé",
      failed: "Action requise",
    },
    model: "Modèle",
    microphone: "Microphone",
    shortcut: "Raccourci",
    defaultMicrophone: "Réglage système",
    noModel: "Choisir un modèle",
    privacyTitle: "Rien ne quitte votre Mac",
    privacyBody:
      "La dictée locale fonctionne hors ligne et sans compte. Le Cloud n’est jamais choisi silencieusement.",
    mode: "Mode",
    faithful: "Fidèle",
    route: "Route de traitement",
  },
} as const;

export const HomeDashboard = () => {
  const { i18n } = useTranslation();
  const { settings } = useSettings();
  const { currentModel, models } = useModelStore();
  const [pipeline, setPipeline] = useState<PipelineState>(
    INITIAL_PIPELINE_STATE,
  );

  useEffect(() => {
    let mounted = true;
    commands
      .getPipelineState()
      .then((state) => mounted && setPipeline(state))
      .catch(() => undefined);

    const unlisten = events.pipelineState.listen((event) => {
      setPipeline(event.payload);
    });

    return () => {
      mounted = false;
      unlisten.then((dispose) => dispose());
    };
  }, []);

  const currentModelName = useMemo(
    () => models.find((model) => model.id === currentModel)?.name,
    [currentModel, models],
  );
  const shortcut = settings?.bindings?.transcribe?.current_binding;
  const microphone = settings?.selected_microphone;

  return (
    <HomeDashboardView
      language={i18n.resolvedLanguage}
      pipeline={pipeline}
      modelName={currentModelName}
      shortcut={shortcut}
      microphone={microphone}
    />
  );
};

interface HomeDashboardViewProps {
  language?: string;
  pipeline: PipelineState;
  modelName?: string;
  shortcut?: string;
  microphone?: string | null;
}

export const HomeDashboardView = ({
  language,
  pipeline,
  modelName,
  shortcut,
  microphone,
}: HomeDashboardViewProps) => {
  const copy = COPY[language?.startsWith("fr") ? "fr" : "en"];
  const isActive = !["idle", "cancelled", "failed"].includes(pipeline.phase);

  return (
    <div className="product-page">
      <section className="hero-card" aria-live="polite">
        <div className="flex items-start justify-between gap-6">
          <div>
            <p className="product-eyebrow">{copy.eyebrow}</p>
            <h1 className="product-title">{copy.title}</h1>
            <p className="product-subtitle">{copy.subtitle}</p>
          </div>
          <div className={`pipeline-indicator ${isActive ? "is-active" : ""}`}>
            <span className="pipeline-dot" aria-hidden="true" />
            <span>{copy.status[pipeline.phase]}</span>
          </div>
        </div>

        <div className="hero-meta">
          <span className="route-badge">
            <CloudOff size={14} />
            {copy.local}
          </span>
          <span className="privacy-badge">
            <ShieldCheck size={14} />
            {copy.private}
          </span>
        </div>
      </section>

      <section className="status-grid" aria-label="Pressay status">
        <StatusCard
          icon={<Sparkles size={18} />}
          label={copy.mode}
          value={copy.faithful}
        />
        <StatusCard
          icon={<Command size={18} />}
          label={copy.shortcut}
          value={shortcut || "⌥ Space"}
          mono
        />
        <StatusCard
          icon={<Mic2 size={18} />}
          label={copy.microphone}
          value={microphone || copy.defaultMicrophone}
        />
        <StatusCard
          icon={<CheckCircle2 size={18} />}
          label={copy.model}
          value={modelName || copy.noModel}
        />
      </section>

      <section className="privacy-card">
        <div className="privacy-card-icon" aria-hidden="true">
          <ShieldCheck size={20} />
        </div>
        <div>
          <h2>{copy.privacyTitle}</h2>
          <p>{copy.privacyBody}</p>
        </div>
        <div className="route-summary">
          <span>{copy.route}</span>
          <strong>{copy.local}</strong>
        </div>
      </section>
    </div>
  );
};

const StatusCard = ({
  icon,
  label,
  value,
  mono = false,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  mono?: boolean;
}) => (
  <article className="status-card">
    <div className="status-card-icon" aria-hidden="true">
      {icon}
    </div>
    <div className="min-w-0">
      <p>{label}</p>
      <strong className={mono ? "technical-label" : undefined}>{value}</strong>
    </div>
  </article>
);
