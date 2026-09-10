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
  type Capabilities,
  type CorrectionStatus,
  type PipelineState,
} from "@/bindings";
import { useSettings } from "@/hooks/useSettings";
import { useModelStore } from "@/stores/modelStore";
import { Button } from "@/components/ui/Button";
import { formatKeyCombination } from "@/lib/utils/keyboard";
import { INITIAL_PIPELINE_STATE } from "@/lib/voiceSurface";

const INITIAL_CORRECTION_STATUS: CorrectionStatus = {
  available: false,
  armed: false,
  target_app_name: null,
  expires_in_seconds: 0,
};

const INITIAL_CAPABILITIES: Capabilities = {
  entitlementsEnforced: false,
  tier: "free",
  entitlementSource: "none",
  entitlementState: "local_free",
  entitlementError: null,
  localDictation: "enabled",
  localHistory: "enabled",
  basicDictionary: "enabled",
  deterministicVoiceCommands: "enabled",
  customModes: "upgrade_required",
  appProfiles: "upgrade_required",
  voiceCorrection: "upgrade_required",
  byok: "upgrade_required",
  appleIntelligence: "upgrade_required",
  encryptedSync: "upgrade_required",
  pressayCloud: "upgrade_required",
  directCheckout: "release_gate",
  appStorePurchase: "release_gate",
};

export const HomeDashboard = () => {
  const { settings } = useSettings();
  const { currentModel, models } = useModelStore();
  const [pipeline, setPipeline] = useState<PipelineState>(
    INITIAL_PIPELINE_STATE,
  );
  const [correction, setCorrection] = useState<CorrectionStatus>(
    INITIAL_CORRECTION_STATUS,
  );
  const [capabilities, setCapabilities] =
    useState<Capabilities>(INITIAL_CAPABILITIES);

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
      .getCapabilities()
      .then((value) => mounted && setCapabilities(value))
      .catch(() => undefined);
    return () => {
      mounted = false;
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
  const activeModeId = settings?.active_mode_id ?? "faithful";
  const activeModeName = settings?.pressay_modes?.find(
    (mode) => mode.id === activeModeId,
  )?.name;

  return (
    <HomeDashboardView
      pipeline={pipeline}
      modelName={currentModelName}
      modeId={activeModeId}
      modeName={activeModeName}
      shortcut={shortcut}
      microphone={microphone}
      correction={correction}
      capabilities={capabilities}
      onArmCorrection={armCorrection}
      onCancelCorrection={cancelCorrection}
    />
  );
};

interface HomeDashboardViewProps {
  pipeline: PipelineState;
  modelName?: string;
  modeId?: string;
  modeName?: string;
  shortcut?: string;
  microphone?: string | null;
  correction?: CorrectionStatus;
  capabilities?: Capabilities;
  onArmCorrection?: () => void;
  onCancelCorrection?: () => void;
}

export const HomeDashboardView = ({
  pipeline,
  modelName,
  modeId = "faithful",
  modeName,
  shortcut,
  microphone,
  correction = INITIAL_CORRECTION_STATUS,
  capabilities = INITIAL_CAPABILITIES,
  onArmCorrection,
  onCancelCorrection,
}: HomeDashboardViewProps) => {
  const { t } = useTranslation();
  const voice = pipeline.voice;
  const isActive = !["hidden", "cancelled", "failed"].includes(voice.phase);
  const routeIsLocal = voice.route === "local_stt";
  const commandSamples = [1, 2, 3].map((sample) =>
    t(`signalOs.dashboard.voiceCommandSamples.${sample}`),
  );
  const activeModeLabel = t(`pressay.modes.builtins.${modeId}.name`, {
    defaultValue: modeName ?? t("signalOs.dashboard.faithful"),
  });
  const shortcutLabel = shortcut
    ? formatKeyCombination(shortcut, "macos")
    : "⌥ + Space";

  return (
    <div className="product-page">
      <section className="hero-card" aria-live="polite">
        <div className="flex items-start justify-between gap-6">
          <div>
            <p className="product-eyebrow">{t("signalOs.dashboard.eyebrow")}</p>
            <h1 className="product-title">{t("signalOs.dashboard.title")}</h1>
            <p className="product-subtitle">
              {t("signalOs.dashboard.subtitle")}
            </p>
          </div>
          <div className={`pipeline-indicator ${isActive ? "is-active" : ""}`}>
            <span className="pipeline-dot" aria-hidden="true" />
            <span>{t(`signalOs.dashboard.status.${voice.phase}`)}</span>
          </div>
        </div>

        <div className="hero-meta">
          <span className={`route-badge route-${voice.route}`}>
            {routeIsLocal ? <CloudOff size={14} /> : <Sparkles size={14} />}
            {t(`signalOs.dashboard.routes.${voice.route}`)}
          </span>
          <span className="privacy-badge">
            <ShieldCheck size={14} />
            {t("signalOs.dashboard.private")}
          </span>
          <span className="entitlement-badge">
            {capabilities.tier === "pro"
              ? t("signalOs.dashboard.proPlan")
              : capabilities.entitlementsEnforced
                ? t("signalOs.dashboard.freePlan")
                : t("signalOs.dashboard.previewPlan")}
          </span>
        </div>
      </section>

      <section
        className="status-grid"
        aria-label={t("signalOs.dashboard.statusLabel")}
      >
        <StatusCard
          icon={<Sparkles size={18} />}
          label={t("signalOs.dashboard.mode")}
          value={activeModeLabel}
        />
        <StatusCard
          icon={<Command size={18} />}
          label={t("signalOs.dashboard.shortcut")}
          value={shortcutLabel}
          mono
        />
        <StatusCard
          icon={<Mic2 size={18} />}
          label={t("signalOs.dashboard.microphone")}
          value={microphone || t("signalOs.dashboard.defaultMicrophone")}
        />
        <StatusCard
          icon={<CheckCircle2 size={18} />}
          label={t("signalOs.dashboard.model")}
          value={modelName || t("signalOs.dashboard.noModel")}
        />
      </section>

      <section className="voice-command-card">
        <div className="voice-command-card-heading">
          <div className="voice-command-card-icon" aria-hidden="true">
            <Command size={18} />
          </div>
          <div>
            <h2>{t("signalOs.dashboard.voiceCommandsTitle")}</h2>
            <p>{t("signalOs.dashboard.voiceCommandsBody")}</p>
          </div>
          <span className="route-badge route-local_stt">
            {t("signalOs.dashboard.local")}
          </span>
        </div>
        <div className="voice-command-examples">
          {commandSamples.map((sample) => (
            <code key={sample}>
              {t("signalOs.dashboard.voiceCommandsWake")}, {sample}
            </code>
          ))}
        </div>
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
              {correction.armed
                ? t("signalOs.dashboard.correctionArmed")
                : t("signalOs.dashboard.correctionTitle")}
            </h2>
            <p>
              {correction.armed
                ? t("signalOs.dashboard.correctionArmedBody", {
                    app:
                      correction.target_app_name ||
                      t("signalOs.dashboard.originalApp"),
                  })
                : t("signalOs.dashboard.correctionBody")}
            </p>
            {!correction.armed ? (
              <small>{t("signalOs.dashboard.correctionDisclosure")}</small>
            ) : null}
          </div>
          {correction.armed ? (
            <Button variant="secondary" onClick={onCancelCorrection}>
              <X size={14} />
              {t("signalOs.dashboard.correctionCancel")}
            </Button>
          ) : (
            <Button onClick={onArmCorrection} disabled={isActive}>
              <Mic2 size={14} />
              {t("signalOs.dashboard.correctionAction")}
            </Button>
          )}
        </section>
      ) : null}

      <section className="privacy-card">
        <div className="privacy-card-icon" aria-hidden="true">
          <ShieldCheck size={20} />
        </div>
        <div>
          <h2>{t("signalOs.dashboard.privacyTitle")}</h2>
          <p>{t("signalOs.dashboard.privacyBody")}</p>
        </div>
        <div className="route-summary">
          <span>{t("signalOs.dashboard.route")}</span>
          <strong>{t("signalOs.dashboard.local")}</strong>
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
