import { useEffect, useMemo, useState } from "react";
import {
  CheckCircle2,
  CloudOff,
  Command,
  Mic2,
  RotateCcw,
  ShieldCheck,
  Sparkles,
  X,
} from "lucide-react";
import { useTranslation } from "react-i18next";
import { listen } from "@tauri-apps/api/event";
import { toast } from "sonner";
import {
  commands,
  events,
  type CorrectionStatus,
  type PipelineState,
} from "@/bindings";
import { useSettings } from "@/hooks/useSettings";
import { useModelStore } from "@/stores/modelStore";
import { Button } from "@/components/ui/Button";

const INITIAL_PIPELINE_STATE: PipelineState = {
  phase: "idle",
  operation_id: 0,
  binding_id: null,
  failure: null,
};

const INITIAL_CORRECTION_STATUS: CorrectionStatus = {
  available: false,
  armed: false,
  target_app_name: null,
  expires_in_seconds: 0,
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
    correctionTitle: "Correct the last result",
    correctionBody:
      "Arm correction, return to the original app, then dictate only the change you want.",
    correctionDisclosure:
      "Your configured text provider processes the original and instruction. If it is remote, both leave this Mac.",
    correctionAction: "Correct with voice",
    correctionArmed: "Waiting for your correction",
    correctionArmedBody: "Return to {{app}} and use your dictation shortcut.",
    correctionCancel: "Cancel",
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
    correctionTitle: "Corriger le dernier résultat",
    correctionBody:
      "Armez la correction, revenez dans l’application d’origine, puis dictez uniquement la modification souhaitée.",
    correctionDisclosure:
      "Votre fournisseur de texte traite l’original et l’instruction. S’il est distant, les deux quittent ce Mac.",
    correctionAction: "Corriger à la voix",
    correctionArmed: "En attente de votre correction",
    correctionArmedBody:
      "Revenez dans {{app}} et utilisez votre raccourci de dictée.",
    correctionCancel: "Annuler",
  },
} as const;

export const HomeDashboard = () => {
  const { i18n } = useTranslation();
  const { settings } = useSettings();
  const { currentModel, models } = useModelStore();
  const [pipeline, setPipeline] = useState<PipelineState>(
    INITIAL_PIPELINE_STATE,
  );
  const [correction, setCorrection] = useState<CorrectionStatus>(
    INITIAL_CORRECTION_STATUS,
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

  useEffect(() => {
    let mounted = true;
    commands
      .getCorrectionStatus()
      .then((status) => mounted && setCorrection(status))
      .catch(() => undefined);
    const unlisten = listen<CorrectionStatus>("correction-status", (event) => {
      setCorrection(event.payload);
    });
    return () => {
      mounted = false;
      unlisten.then((dispose) => dispose());
    };
  }, []);

  const armCorrection = async () => {
    try {
      const result = await commands.armVoiceCorrection();
      if (result.status === "error") {
        toast.error(result.error);
        return;
      }
      setCorrection(result.data);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : String(error));
    }
  };

  const cancelCorrection = async () => {
    try {
      setCorrection(await commands.cancelVoiceCorrection());
    } catch (error) {
      toast.error(error instanceof Error ? error.message : String(error));
    }
  };

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
      correction={correction}
      onArmCorrection={armCorrection}
      onCancelCorrection={cancelCorrection}
    />
  );
};

interface HomeDashboardViewProps {
  language?: string;
  pipeline: PipelineState;
  modelName?: string;
  shortcut?: string;
  microphone?: string | null;
  correction?: CorrectionStatus;
  onArmCorrection?: () => void;
  onCancelCorrection?: () => void;
}

export const HomeDashboardView = ({
  language,
  pipeline,
  modelName,
  shortcut,
  microphone,
  correction = INITIAL_CORRECTION_STATUS,
  onArmCorrection,
  onCancelCorrection,
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

      {correction.available ? (
        <section
          className={`correction-card ${correction.armed ? "is-armed" : ""}`}
        >
          <div className="correction-card-icon" aria-hidden="true">
            <RotateCcw size={18} />
          </div>
          <div>
            <h2>
              {correction.armed ? copy.correctionArmed : copy.correctionTitle}
            </h2>
            <p>
              {correction.armed
                ? copy.correctionArmedBody.replace(
                    "{{app}}",
                    correction.target_app_name || "the original app",
                  )
                : copy.correctionBody}
            </p>
            {!correction.armed ? (
              <small>{copy.correctionDisclosure}</small>
            ) : null}
          </div>
          {correction.armed ? (
            <Button variant="secondary" onClick={onCancelCorrection}>
              <X size={14} />
              {copy.correctionCancel}
            </Button>
          ) : (
            <Button onClick={onArmCorrection} disabled={isActive}>
              <Mic2 size={14} />
              {copy.correctionAction}
            </Button>
          )}
        </section>
      ) : null}

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
