import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  AppWindow,
  Check,
  Cloud,
  Download,
  KeyRound,
  Laptop,
  Plus,
  Trash2,
  Upload,
} from "lucide-react";
import { toast } from "sonner";
import { commands } from "@/bindings";
import type {
  AppProfile,
  OutputBehavior,
  PressayMode,
  ProcessingRoute,
  ProductivityConfig,
} from "@/bindings";
import { useProductivityStore } from "@/stores/productivityStore";
import { useModelStore } from "@/stores/modelStore";
import { useSettingsStore } from "@/stores/settingsStore";
import { SELECTABLE_LANGUAGES } from "@/lib/constants/languages";
import { navigateToAppSection } from "@/lib/appNavigation";
import { Button } from "@/components/ui/Button";
import { Input } from "@/components/ui/Input";
import { Select } from "@/components/ui/Select";
import { Textarea } from "@/components/ui/Textarea";
import { ProductivityPage } from "./ProductivityPage";

const routeIcons: Record<ProcessingRoute, typeof Laptop> = {
  local: Laptop,
  byok: KeyRound,
  pressay_cloud: Cloud,
};

interface RouteAvailability {
  ready: boolean;
  detail: string;
}

const routeMeta = (
  t: ReturnType<typeof useTranslation>["t"],
): Record<ProcessingRoute, { label: string; detail: string }> => ({
  local: {
    label: t("pressay.routes.local.label"),
    detail: t("pressay.routes.local.detail"),
  },
  byok: {
    label: t("pressay.routes.byok.label"),
    detail: t("pressay.routes.byok.detail"),
  },
  pressay_cloud: {
    label: t("pressay.routes.pressay_cloud.label"),
    detail: t("pressay.routes.pressay_cloud.detail"),
  },
});

const builtinCopy = (
  mode: PressayMode,
  t: ReturnType<typeof useTranslation>["t"],
): PressayMode =>
  mode.is_builtin
    ? {
        ...mode,
        name: t(`pressay.modes.builtins.${mode.id}.name`),
        description: t(`pressay.modes.builtins.${mode.id}.description`),
      }
    : mode;

const blankMode = (): PressayMode => ({
  id: `mode_${Date.now()}`,
  name: "",
  description: "",
  route: "local",
  steps: [
    { id: "normalize", kind: "normalize" },
    { id: "dictionary", kind: "dictionary" },
  ],
  tone: null,
  length: null,
  language: null,
  is_builtin: false,
});

const blankProfile = (modeId: string): AppProfile => ({
  id: `profile_${Date.now()}`,
  bundle_id: "",
  app_name: "",
  priority: 0,
  mode_id: modeId,
  language: null,
  microphone: null,
  model: null,
  output: "paste",
});

interface ModesSettingsViewProps {
  config: ProductivityConfig;
  saving?: boolean;
  error?: string | null;
  onActivate: (modeId: string) => Promise<unknown> | unknown;
  onUseOnce: (modeId: string) => Promise<unknown> | unknown;
  onSaveMode: (mode: PressayMode) => Promise<boolean> | boolean;
  onDeleteMode: (modeId: string) => Promise<unknown> | unknown;
  onSaveProfile: (profile: AppProfile) => Promise<boolean> | boolean;
  onDeleteProfile: (profileId: string) => Promise<unknown> | unknown;
  onExport?: () => Promise<unknown> | unknown;
  onImport?: () => Promise<unknown> | unknown;
  onConfigureRoute?: (route: ProcessingRoute) => void;
  modelOptions?: Array<{ value: string; label: string }>;
  microphoneOptions?: Array<{ value: string; label: string }>;
  routeAvailability?: Record<ProcessingRoute, RouteAvailability>;
}

export const ModesSettingsView = ({
  config,
  saving = false,
  error,
  onActivate,
  onUseOnce,
  onSaveMode,
  onDeleteMode,
  onSaveProfile,
  onDeleteProfile,
  onExport,
  onImport,
  onConfigureRoute,
  modelOptions = [],
  microphoneOptions = [],
  routeAvailability = {
    local: { ready: true, detail: "" },
    byok: { ready: false, detail: "" },
    pressay_cloud: { ready: false, detail: "" },
  },
}: ModesSettingsViewProps) => {
  const { t } = useTranslation();
  const routes = routeMeta(t);
  const [showModeForm, setShowModeForm] = useState(false);
  const [modeDraft, setModeDraft] = useState<PressayMode>(blankMode);
  const [showProfileForm, setShowProfileForm] = useState(false);
  const [profileDraft, setProfileDraft] = useState<AppProfile>(() =>
    blankProfile(config.active_mode_id),
  );

  const modeOptions = useMemo(
    () =>
      config.modes.map((mode) => ({
        value: mode.id,
        label: builtinCopy(mode, t).name,
      })),
    [config.modes, t],
  );

  const changeRoute = (route: ProcessingRoute) => {
    setModeDraft((current) => ({
      ...current,
      route,
      steps:
        route === "local"
          ? current.steps.filter((step) => step.kind !== "transform")
          : [
              ...current.steps.filter((step) => step.kind !== "transform"),
              {
                id: "transform",
                kind: "transform",
                instruction:
                  "Transform ${transcript} while preserving meaning.",
              },
            ],
    }));
  };

  const submitMode = async () => {
    const saved = await onSaveMode({
      ...modeDraft,
      name: modeDraft.name.trim(),
      description: modeDraft.description.trim(),
    });
    if (saved) {
      setModeDraft(blankMode());
      setShowModeForm(false);
    }
  };

  const submitProfile = async () => {
    const saved = await onSaveProfile({
      ...profileDraft,
      bundle_id: profileDraft.bundle_id.trim(),
      app_name: profileDraft.app_name.trim(),
    });
    if (saved) {
      setProfileDraft(blankProfile(config.active_mode_id));
      setShowProfileForm(false);
    }
  };

  return (
    <ProductivityPage
      eyebrow={t("pressay.modes.eyebrow")}
      title={t("pressay.modes.title")}
      description={t("pressay.modes.description")}
      action={
        <div className="productivity-header-actions">
          {onImport ? (
            <Button variant="ghost" disabled={saving} onClick={onImport}>
              <Upload size={14} aria-hidden="true" />
              {t("common.import")}
            </Button>
          ) : null}
          {onExport ? (
            <Button variant="ghost" disabled={saving} onClick={onExport}>
              <Download size={14} aria-hidden="true" />
              {t("common.export")}
            </Button>
          ) : null}
          <Button
            variant="secondary"
            onClick={() => setShowModeForm((visible) => !visible)}
          >
            <Plus size={14} aria-hidden="true" />
            {t("pressay.modes.new")}
          </Button>
        </div>
      }
    >
      {error ? <p className="productivity-error">{error}</p> : null}

      {showModeForm ? (
        <section
          className="productivity-editor"
          aria-label={t("pressay.modes.editorLabel")}
        >
          <div className="productivity-editor-grid">
            <label>
              <span>{t("common.name")}</span>
              <Input
                value={modeDraft.name}
                maxLength={80}
                placeholder={t("pressay.modes.namePlaceholder")}
                onChange={(event) =>
                  setModeDraft((current) => ({
                    ...current,
                    name: event.target.value,
                  }))
                }
              />
            </label>
            <label>
              <span>{t("pressay.modes.route")}</span>
              <Select
                ariaLabel={t("pressay.modes.route")}
                value={modeDraft.route}
                isClearable={false}
                options={Object.entries(routes).map(([value, meta]) => ({
                  value,
                  label: meta.label,
                }))}
                onChange={(value) => changeRoute(value as ProcessingRoute)}
              />
            </label>
          </div>
          <label>
            <span>{t("common.description")}</span>
            <Input
              value={modeDraft.description}
              maxLength={280}
              placeholder={t("pressay.modes.descriptionPlaceholder")}
              onChange={(event) =>
                setModeDraft((current) => ({
                  ...current,
                  description: event.target.value,
                }))
              }
            />
          </label>
          {modeDraft.route !== "local" ? (
            <label>
              <span>{t("pressay.modes.instruction")}</span>
              <Textarea
                value={
                  modeDraft.steps.find((step) => step.kind === "transform")
                    ?.instruction ?? ""
                }
                onChange={(event) =>
                  setModeDraft((current) => ({
                    ...current,
                    steps: current.steps.map((step) =>
                      step.kind === "transform"
                        ? { ...step, instruction: event.target.value }
                        : step,
                    ),
                  }))
                }
              />
              <small>{t("pressay.modes.variables")}</small>
            </label>
          ) : null}
          <div className="productivity-editor-actions">
            <Button variant="ghost" onClick={() => setShowModeForm(false)}>
              {t("common.cancel")}
            </Button>
            <Button
              disabled={
                saving ||
                !modeDraft.name.trim() ||
                !modeDraft.description.trim()
              }
              onClick={submitMode}
            >
              {t("pressay.modes.save")}
            </Button>
          </div>
        </section>
      ) : null}

      <section className="mode-grid" aria-label={t("pressay.modes.available")}>
        {config.modes.map((mode) => {
          const displayMode = builtinCopy(mode, t);
          const route = routes[mode.route];
          const RouteIcon = routeIcons[mode.route];
          const availability = routeAvailability[mode.route];
          const active = mode.id === config.active_mode_id;
          return (
            <article
              key={mode.id}
              className={`mode-card ${active ? "is-active" : ""}`}
            >
              <div className="mode-card-topline">
                <span className={`mode-route is-${mode.route}`}>
                  <RouteIcon size={13} aria-hidden="true" />
                  {route.label}
                </span>
                {active ? (
                  <span className="mode-active-label">
                    <Check size={13} aria-hidden="true" />
                    {t("pressay.modes.active")}
                  </span>
                ) : null}
              </div>
              <h2>{displayMode.name}</h2>
              <p>{displayMode.description}</p>
              <div className="mode-card-footer">
                <span
                  className={`mode-readiness ${availability.ready ? "is-ready" : "is-blocked"}`}
                >
                  {availability.ready
                    ? route.detail
                    : availability.detail || t("pressay.routes.setupRequired")}
                </span>
                <div>
                  {!mode.is_builtin ? (
                    <button
                      type="button"
                      className="icon-action is-danger"
                      aria-label={t("pressay.modes.deleteLabel", {
                        name: displayMode.name,
                      })}
                      onClick={() => onDeleteMode(mode.id)}
                    >
                      <Trash2 size={14} />
                    </button>
                  ) : null}
                  {!availability.ready && onConfigureRoute ? (
                    <Button
                      size="sm"
                      variant="secondary"
                      disabled={saving}
                      onClick={() => onConfigureRoute(mode.route)}
                    >
                      {t("cloud.sync.enable")}
                    </Button>
                  ) : (
                    <>
                      <Button
                        size="sm"
                        variant="ghost"
                        disabled={saving}
                        onClick={() => onUseOnce(mode.id)}
                      >
                        {t("pressay.modes.useOnce")}
                      </Button>
                      <Button
                        size="sm"
                        variant={active ? "primary-soft" : "secondary"}
                        disabled={active || saving}
                        onClick={() => onActivate(mode.id)}
                      >
                        {active
                          ? t("pressay.modes.selected")
                          : t("pressay.modes.useMode")}
                      </Button>
                    </>
                  )}
                </div>
              </div>
            </article>
          );
        })}
      </section>

      <section className="productivity-section">
        <div className="productivity-section-heading">
          <div>
            <p className="product-eyebrow">{t("pressay.profiles.eyebrow")}</p>
            <h2>{t("pressay.profiles.title")}</h2>
            <p>{t("pressay.profiles.description")}</p>
          </div>
          <Button
            size="sm"
            variant="ghost"
            onClick={() => setShowProfileForm((visible) => !visible)}
          >
            <Plus size={14} />
            {t("pressay.profiles.add")}
          </Button>
        </div>

        {showProfileForm ? (
          <div className="profile-editor">
            <Input
              aria-label={t("pressay.profiles.appName")}
              placeholder={t("pressay.profiles.appPlaceholder")}
              value={profileDraft.app_name}
              onChange={(event) =>
                setProfileDraft((current) => ({
                  ...current,
                  app_name: event.target.value,
                }))
              }
            />
            <Input
              aria-label={t("pressay.profiles.bundleId")}
              placeholder={t("pressay.profiles.bundlePlaceholder")}
              value={profileDraft.bundle_id}
              onChange={(event) =>
                setProfileDraft((current) => ({
                  ...current,
                  bundle_id: event.target.value,
                }))
              }
            />
            <Select
              ariaLabel={t("pressay.profiles.mode")}
              value={profileDraft.mode_id}
              isClearable={false}
              options={modeOptions}
              onChange={(value) =>
                setProfileDraft((current) => ({
                  ...current,
                  mode_id: value ?? config.active_mode_id,
                }))
              }
            />
            <Select
              ariaLabel={t("pressay.profiles.output")}
              value={profileDraft.output ?? "paste"}
              isClearable={false}
              options={[
                { value: "paste", label: t("pressay.profiles.outputs.paste") },
                { value: "copy", label: t("pressay.profiles.outputs.copy") },
                { value: "type", label: t("pressay.profiles.outputs.type") },
              ]}
              onChange={(value) =>
                setProfileDraft((current) => ({
                  ...current,
                  output: (value ?? "paste") as OutputBehavior,
                }))
              }
            />
            <Select
              ariaLabel={t("pressay.profiles.language")}
              value={profileDraft.language ?? "__default__"}
              isClearable={false}
              options={[
                {
                  value: "__default__",
                  label: t("pressay.profiles.defaultLanguage"),
                },
                ...SELECTABLE_LANGUAGES,
              ]}
              onChange={(value) =>
                setProfileDraft((current) => ({
                  ...current,
                  language: value === "__default__" ? null : value,
                }))
              }
            />
            <Select
              ariaLabel={t("pressay.profiles.model")}
              value={profileDraft.model ?? "__default__"}
              isClearable={false}
              options={[
                {
                  value: "__default__",
                  label: t("pressay.profiles.defaultModel"),
                },
                ...modelOptions,
              ]}
              onChange={(value) =>
                setProfileDraft((current) => ({
                  ...current,
                  model: value === "__default__" ? null : value,
                }))
              }
            />
            <Select
              ariaLabel={t("pressay.profiles.microphone")}
              value={profileDraft.microphone ?? "__default__"}
              isClearable={false}
              options={[
                {
                  value: "__default__",
                  label: t("pressay.profiles.defaultMicrophone"),
                },
                ...microphoneOptions,
              ]}
              onChange={(value) =>
                setProfileDraft((current) => ({
                  ...current,
                  microphone: value === "__default__" ? null : value,
                }))
              }
            />
            <Button
              disabled={
                saving ||
                !profileDraft.app_name.trim() ||
                !profileDraft.bundle_id.trim()
              }
              onClick={submitProfile}
            >
              {t("common.save")}
            </Button>
          </div>
        ) : null}

        <div className="profile-list">
          {config.profiles.length === 0 ? (
            <div className="productivity-empty">
              <AppWindow size={18} />
              <p>{t("pressay.profiles.empty")}</p>
            </div>
          ) : (
            config.profiles.map((profile) => (
              <div key={profile.id} className="profile-row">
                <AppWindow size={17} aria-hidden="true" />
                <div>
                  <strong>{profile.app_name}</strong>
                  <span className="technical-label">{profile.bundle_id}</span>
                  {profile.language || profile.model || profile.microphone ? (
                    <span className="technical-label profile-overrides">
                      {[profile.language, profile.model, profile.microphone]
                        .filter(Boolean)
                        .join(" · ")}
                    </span>
                  ) : null}
                </div>
                <span>
                  {config.modes.find((mode) => mode.id === profile.mode_id)
                    ?.name ?? profile.mode_id}
                </span>
                <span>{profile.output ?? "paste"}</span>
                <button
                  type="button"
                  className="icon-action is-danger"
                  aria-label={t("pressay.profiles.deleteLabel", {
                    name: profile.app_name,
                  })}
                  onClick={() => onDeleteProfile(profile.id)}
                >
                  <Trash2 size={14} />
                </button>
              </div>
            ))
          )}
        </div>
      </section>
    </ProductivityPage>
  );
};

export const ModesSettings = () => {
  const { t } = useTranslation();
  const config = useProductivityStore((state) => state.config);
  const loading = useProductivityStore((state) => state.loading);
  const saving = useProductivityStore((state) => state.saving);
  const error = useProductivityStore((state) => state.error);
  const initialize = useProductivityStore((state) => state.initialize);
  const setActiveMode = useProductivityStore((state) => state.setActiveMode);
  const useModeOnce = useProductivityStore((state) => state.useModeOnce);
  const saveMode = useProductivityStore((state) => state.saveMode);
  const deleteMode = useProductivityStore((state) => state.deleteMode);
  const saveProfile = useProductivityStore((state) => state.saveProfile);
  const deleteProfile = useProductivityStore((state) => state.deleteProfile);
  const refreshProductivity = useProductivityStore((state) => state.refresh);
  const models = useModelStore((state) => state.models);
  const initializeModels = useModelStore((state) => state.initialize);
  const audioDevices = useSettingsStore((state) => state.audioDevices);
  const settings = useSettingsStore((state) => state.settings);
  const providerConnections = useSettingsStore(
    (state) => state.postProcessProviderConnections,
  );
  const refreshAudioDevices = useSettingsStore(
    (state) => state.refreshAudioDevices,
  );

  useEffect(() => {
    void initialize();
    void initializeModels();
    void refreshAudioDevices();
  }, [initialize, initializeModels, refreshAudioDevices]);

  if (!config) {
    return (
      <div className="productivity-loading">
        {loading
          ? t("pressay.modes.loading")
          : (error ?? t("pressay.modes.unavailable"))}
      </div>
    );
  }

  const selectedProvider = settings?.post_process_providers?.find(
    (provider) => provider.id === settings.post_process_provider_id,
  );
  const selectedProviderId = selectedProvider?.id ?? "";
  const selectedModel =
    settings?.post_process_models?.[selectedProviderId]?.trim() ?? "";
  const hasProviderSecret =
    settings?.post_process_api_keys_configured?.[selectedProviderId] ?? false;
  const providerConnectionVerified =
    selectedProviderId === "apple_intelligence" ||
    providerConnections[selectedProviderId]?.status === "valid";
  const byokReady =
    providerConnectionVerified &&
    (selectedProviderId === "apple_intelligence" ||
      (selectedProviderId === "custom"
        ? Boolean(selectedProvider?.base_url?.trim() && selectedModel)
        : Boolean(selectedProviderId && hasProviderSecret && selectedModel)));
  const cloudReady = Boolean(
    settings?.pressay_cloud_account_id && settings.pressay_cloud_device_id,
  );
  const routeAvailability: Record<ProcessingRoute, RouteAvailability> = {
    local: { ready: true, detail: t("pressay.routes.local.detail") },
    byok: {
      ready: byokReady,
      detail: byokReady
        ? t("pressay.routes.byok.detail")
        : t("pressay.routes.byok.notConfigured"),
    },
    pressay_cloud: {
      ready: cloudReady,
      detail: cloudReady
        ? t("pressay.routes.pressay_cloud.detail")
        : t("pressay.routes.pressay_cloud.notConnected"),
    },
  };

  const exportConfig = async () => {
    try {
      const result = await commands.exportProductivityConfig();
      if (result.status === "error") {
        toast.error(result.error);
      } else if (!result.data.cancelled) {
        toast.success(t("pressay.transfer.exported"));
      }
    } catch (error) {
      toast.error(error instanceof Error ? error.message : String(error));
    }
  };

  const importConfig = async () => {
    try {
      const result = await commands.importProductivityConfig();
      if (result.status === "error") {
        toast.error(result.error);
        return;
      }
      if (result.data.cancelled) return;
      await refreshProductivity();
      const report = result.data;
      const summary = t("pressay.transfer.summary", {
        modes: report.modes_added,
        profiles: report.profiles_added,
        terms: report.dictionary_added,
      });
      toast.success(t("pressay.transfer.imported"), {
        description:
          report.conflicts_preserved > 0
            ? `${summary} · ${t("pressay.transfer.conflicts", { count: report.conflicts_preserved })}`
            : summary,
      });
    } catch (error) {
      toast.error(error instanceof Error ? error.message : String(error));
    }
  };

  return (
    <ModesSettingsView
      config={config}
      saving={saving}
      error={error}
      onActivate={setActiveMode}
      onUseOnce={useModeOnce}
      onSaveMode={saveMode}
      onDeleteMode={deleteMode}
      onSaveProfile={saveProfile}
      onDeleteProfile={deleteProfile}
      onExport={exportConfig}
      onImport={importConfig}
      onConfigureRoute={(route) =>
        navigateToAppSection(route === "byok" ? "postprocessing" : "account")
      }
      routeAvailability={routeAvailability}
      modelOptions={models
        .filter((model) => model.is_downloaded)
        .map((model) => ({ value: model.id, label: model.name }))}
      microphoneOptions={audioDevices
        .filter((device) => !device.is_default)
        .map((device) => ({ value: device.name, label: device.name }))}
    />
  );
};
