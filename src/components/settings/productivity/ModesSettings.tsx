import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  AppWindow,
  Check,
  Cloud,
  KeyRound,
  Laptop,
  Plus,
  Trash2,
} from "lucide-react";
import type {
  AppProfile,
  OutputBehavior,
  PressayMode,
  ProcessingRoute,
  ProductivityConfig,
} from "@/bindings";
import { useProductivityStore } from "@/stores/productivityStore";
import { Button } from "@/components/ui/Button";
import { Input } from "@/components/ui/Input";
import { Select } from "@/components/ui/Select";
import { Textarea } from "@/components/ui/Textarea";
import { ProductivityPage } from "./ProductivityPage";

const routeMeta: Record<
  ProcessingRoute,
  { label: string; detail: string; icon: typeof Laptop }
> = {
  local: {
    label: "Local",
    detail: "Nothing leaves this Mac",
    icon: Laptop,
  },
  byok: {
    label: "BYOK",
    detail: "Directly through your provider",
    icon: KeyRound,
  },
  pressay_cloud: {
    label: "Pressay Cloud",
    detail: "Requires an explicit account connection",
    icon: Cloud,
  },
};

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
  onSaveMode: (mode: PressayMode) => Promise<boolean> | boolean;
  onDeleteMode: (modeId: string) => Promise<unknown> | unknown;
  onSaveProfile: (profile: AppProfile) => Promise<boolean> | boolean;
  onDeleteProfile: (profileId: string) => Promise<unknown> | unknown;
}

export const ModesSettingsView = ({
  config,
  saving = false,
  error,
  onActivate,
  onSaveMode,
  onDeleteMode,
  onSaveProfile,
  onDeleteProfile,
}: ModesSettingsViewProps) => {
  const { t } = useTranslation();
  const [showModeForm, setShowModeForm] = useState(false);
  const [modeDraft, setModeDraft] = useState<PressayMode>(blankMode);
  const [showProfileForm, setShowProfileForm] = useState(false);
  const [profileDraft, setProfileDraft] = useState<AppProfile>(() =>
    blankProfile(config.active_mode_id),
  );

  const modeOptions = useMemo(
    () => config.modes.map((mode) => ({ value: mode.id, label: mode.name })),
    [config.modes],
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
      eyebrow={t("pressay.modes.eyebrow", { defaultValue: "WORKFLOW" })}
      title={t("pressay.modes.title", { defaultValue: "Modes" })}
      description={t("pressay.modes.description", {
        defaultValue:
          "Choose what Pressay does after transcription. A remote route is never selected silently.",
      })}
      action={
        <Button
          variant="secondary"
          onClick={() => setShowModeForm((visible) => !visible)}
        >
          <Plus size={14} aria-hidden="true" />
          {t("pressay.modes.new", { defaultValue: "New mode" })}
        </Button>
      }
    >
      {error ? <p className="productivity-error">{error}</p> : null}

      {showModeForm ? (
        <section
          className="productivity-editor"
          aria-label="Custom mode editor"
        >
          <div className="productivity-editor-grid">
            <label>
              <span>{t("common.name", { defaultValue: "Name" })}</span>
              <Input
                value={modeDraft.name}
                maxLength={80}
                placeholder="Stand-up update"
                onChange={(event) =>
                  setModeDraft((current) => ({
                    ...current,
                    name: event.target.value,
                  }))
                }
              />
            </label>
            <label>
              <span>{t("pressay.modes.route", { defaultValue: "Route" })}</span>
              <Select
                value={modeDraft.route}
                isClearable={false}
                options={Object.entries(routeMeta).map(([value, meta]) => ({
                  value,
                  label: meta.label,
                }))}
                onChange={(value) => changeRoute(value as ProcessingRoute)}
              />
            </label>
          </div>
          <label>
            <span>
              {t("common.description", { defaultValue: "Description" })}
            </span>
            <Input
              value={modeDraft.description}
              maxLength={280}
              placeholder="What this mode produces"
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
              <span>
                {t("pressay.modes.instruction", {
                  defaultValue: "Transformation instruction",
                })}
              </span>
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
              <small>
                {t("pressay.modes.variables", {
                  defaultValue:
                    "Variables: ${transcript}, ${selected}, ${app_name}, ${custom_words}",
                })}
              </small>
            </label>
          ) : null}
          <div className="productivity-editor-actions">
            <Button variant="ghost" onClick={() => setShowModeForm(false)}>
              {t("common.cancel", { defaultValue: "Cancel" })}
            </Button>
            <Button
              disabled={
                saving ||
                !modeDraft.name.trim() ||
                !modeDraft.description.trim()
              }
              onClick={submitMode}
            >
              {t("pressay.modes.save", { defaultValue: "Save mode" })}
            </Button>
          </div>
        </section>
      ) : null}

      <section className="mode-grid" aria-label="Available modes">
        {config.modes.map((mode) => {
          const route = routeMeta[mode.route];
          const RouteIcon = route.icon;
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
                    {t("pressay.modes.active", { defaultValue: "Active" })}
                  </span>
                ) : null}
              </div>
              <h2>{mode.name}</h2>
              <p>{mode.description}</p>
              <div className="mode-card-footer">
                <span>{route.detail}</span>
                <div>
                  {!mode.is_builtin ? (
                    <button
                      type="button"
                      className="icon-action is-danger"
                      aria-label={`Delete ${mode.name}`}
                      onClick={() => onDeleteMode(mode.id)}
                    >
                      <Trash2 size={14} />
                    </button>
                  ) : null}
                  <Button
                    size="sm"
                    variant={active ? "primary-soft" : "secondary"}
                    disabled={active || saving}
                    onClick={() => onActivate(mode.id)}
                  >
                    {active ? "Selected" : "Use mode"}
                  </Button>
                </div>
              </div>
            </article>
          );
        })}
      </section>

      <section className="productivity-section">
        <div className="productivity-section-heading">
          <div>
            <p className="product-eyebrow">CONTEXT</p>
            <h2>
              {t("pressay.profiles.title", {
                defaultValue: "Application profiles",
              })}
            </h2>
            <p>
              {t("pressay.profiles.description", {
                defaultValue:
                  "Apply a mode and output behavior when a specific macOS bundle ID is active.",
              })}
            </p>
          </div>
          <Button
            size="sm"
            variant="ghost"
            onClick={() => setShowProfileForm((visible) => !visible)}
          >
            <Plus size={14} />
            {t("pressay.profiles.add", { defaultValue: "Add profile" })}
          </Button>
        </div>

        {showProfileForm ? (
          <div className="profile-editor">
            <Input
              aria-label="Application name"
              placeholder="Notion"
              value={profileDraft.app_name}
              onChange={(event) =>
                setProfileDraft((current) => ({
                  ...current,
                  app_name: event.target.value,
                }))
              }
            />
            <Input
              aria-label="Bundle ID"
              placeholder="notion.id"
              value={profileDraft.bundle_id}
              onChange={(event) =>
                setProfileDraft((current) => ({
                  ...current,
                  bundle_id: event.target.value,
                }))
              }
            />
            <Select
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
              value={profileDraft.output ?? "paste"}
              isClearable={false}
              options={[
                { value: "paste", label: "Paste" },
                { value: "copy", label: "Copy" },
                { value: "type", label: "Type" },
              ]}
              onChange={(value) =>
                setProfileDraft((current) => ({
                  ...current,
                  output: (value ?? "paste") as OutputBehavior,
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
              {t("common.save", { defaultValue: "Save" })}
            </Button>
          </div>
        ) : null}

        <div className="profile-list">
          {config.profiles.length === 0 ? (
            <div className="productivity-empty">
              <AppWindow size={18} />
              <p>
                {t("pressay.profiles.empty", {
                  defaultValue: "No application profile yet.",
                })}
              </p>
            </div>
          ) : (
            config.profiles.map((profile) => (
              <div key={profile.id} className="profile-row">
                <AppWindow size={17} aria-hidden="true" />
                <div>
                  <strong>{profile.app_name}</strong>
                  <span className="technical-label">{profile.bundle_id}</span>
                </div>
                <span>
                  {config.modes.find((mode) => mode.id === profile.mode_id)
                    ?.name ?? profile.mode_id}
                </span>
                <span>{profile.output ?? "paste"}</span>
                <button
                  type="button"
                  className="icon-action is-danger"
                  aria-label={`Delete ${profile.app_name} profile`}
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
  const config = useProductivityStore((state) => state.config);
  const loading = useProductivityStore((state) => state.loading);
  const saving = useProductivityStore((state) => state.saving);
  const error = useProductivityStore((state) => state.error);
  const initialize = useProductivityStore((state) => state.initialize);
  const setActiveMode = useProductivityStore((state) => state.setActiveMode);
  const saveMode = useProductivityStore((state) => state.saveMode);
  const deleteMode = useProductivityStore((state) => state.deleteMode);
  const saveProfile = useProductivityStore((state) => state.saveProfile);
  const deleteProfile = useProductivityStore((state) => state.deleteProfile);

  useEffect(() => {
    void initialize();
  }, [initialize]);

  if (!config) {
    return (
      <div className="productivity-loading">
        {loading ? "Loading modes…" : (error ?? "Modes are unavailable.")}
      </div>
    );
  }

  return (
    <ModesSettingsView
      config={config}
      saving={saving}
      error={error}
      onActivate={setActiveMode}
      onSaveMode={saveMode}
      onDeleteMode={deleteMode}
      onSaveProfile={saveProfile}
      onDeleteProfile={deleteProfile}
    />
  );
};
