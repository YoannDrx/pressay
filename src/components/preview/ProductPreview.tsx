/* eslint-disable i18next/no-literal-string -- static browser-only visual fixture */
import { useEffect, useState } from "react";
import {
  BookOpen,
  Cog,
  Cpu,
  House,
  Info,
  Layers3,
  History,
  Sparkles,
  UserRound,
  Search,
  AudioWaveform,
} from "lucide-react";
import type { PipelineState, ProductivityConfig } from "@/bindings";
import type { SidebarSection } from "@/components/Sidebar";
import { HomeDashboardView } from "@/components/dashboard/HomeDashboard";
import PressayWordmark from "@/components/icons/PressayWordmark";
import { PageAtmosphere } from "@/components/layout";
import { OnboardingProgress, WelcomeOnboarding } from "@/components/onboarding";
import {
  DictionarySettingsView,
  ModesSettingsView,
} from "@/components/settings/productivity";
import { INITIAL_PIPELINE_STATE } from "@/lib/voiceSurface";
import { changeAppLanguage } from "@/i18n";

const PREVIEW_PIPELINE: PipelineState = INITIAL_PIPELINE_STATE;

const PREVIEW_SECTIONS = [
  { id: "home", label: "Home", icon: House, group: "primary" },
  { id: "modes", label: "Modes", icon: Layers3, group: "primary" },
  {
    id: "dictionary",
    label: "Dictionary",
    icon: BookOpen,
    group: "primary",
  },
  { id: "history", label: "History", icon: History, group: "primary" },
  {
    id: "general",
    label: "Settings",
    icon: AudioWaveform,
    group: "system",
  },
  { id: "models", label: "Models", icon: Cpu, group: "system" },
  {
    id: "postprocessing",
    label: "Providers",
    icon: Sparkles,
    group: "system",
  },
  { id: "account", label: "Account", icon: UserRound, group: "system" },
  { id: "advanced", label: "Advanced", icon: Cog, group: "secondary" },
  { id: "about", label: "About", icon: Info, group: "secondary" },
];

const PREVIEW_PRODUCTIVITY: ProductivityConfig = {
  schema_version: 2,
  active_mode_id: "faithful",
  modes: [
    {
      id: "faithful",
      name: "Faithful",
      description: "Native punctuation and your local dictionary only.",
      route: "local",
      steps: [
        { id: "normalize", kind: "normalize" },
        { id: "dictionary", kind: "dictionary" },
      ],
      is_builtin: true,
    },
    {
      id: "clean",
      name: "Clean",
      description: "Removes hesitations, repetitions and speech artifacts.",
      route: "local",
      steps: [
        { id: "normalize", kind: "normalize" },
        { id: "dictionary", kind: "dictionary" },
        { id: "clean", kind: "format", instruction: "remove_fillers" },
      ],
      is_builtin: true,
    },
    {
      id: "message",
      name: "Message",
      description: "A short conversational message ready to send.",
      route: "byok",
      steps: [
        { id: "normalize", kind: "normalize" },
        {
          id: "transform",
          kind: "transform",
          instruction: "Transform ${transcript} into a concise message.",
        },
      ],
      is_builtin: true,
    },
    {
      id: "email",
      name: "Email",
      description: "A structured and professional email.",
      route: "byok",
      steps: [
        { id: "normalize", kind: "normalize" },
        {
          id: "transform",
          kind: "transform",
          instruction: "Transform ${transcript} into an email.",
        },
      ],
      is_builtin: true,
    },
    ...[
      ["ai_prompt", "AI prompt", "Turns speech into a structured instruction."],
      ["note", "Note", "Organizes speech into a clear note."],
      [
        "meeting_notes",
        "Meeting notes",
        "Structures decisions and next steps.",
      ],
      ["ticket", "Ticket", "Produces an actionable engineering ticket."],
      ["commit", "Commit", "Generates a concise Conventional Commit."],
      [
        "translation",
        "Translation",
        "Faithfully translates speech into English.",
      ],
      ["summary", "Summary", "Condenses speech without losing key facts."],
      ["tasks", "Tasks", "Extracts a verifiable action list."],
    ].map(([id, name, description]) => ({
      id,
      name,
      description,
      route: "byok" as const,
      steps: [
        { id: "normalize", kind: "normalize" as const },
        {
          id: "transform",
          kind: "transform" as const,
          instruction: "Transform ${transcript} while preserving meaning.",
        },
      ],
      is_builtin: true,
    })),
  ],
  profiles: [],
  dictionary: [
    {
      id: "pressay",
      term: "press say",
      variants: ["presser", "pressé"],
      replacement: "Pressay",
      match_kind: "exact",
      enabled: true,
    },
    {
      id: "macbook",
      term: "Mac Book Pro",
      replacement: "MacBook Pro",
      match_kind: "fuzzy",
      enabled: true,
    },
  ],
};

/** Browser-only visual fixture. The production Tauri runtime never renders it. */
export const ProductPreview = () => {
  const params = new URLSearchParams(window.location.search);
  const requestedScreen = params.get("screen");
  const requestedLocale = params.get("lang");
  useEffect(() => {
    if (requestedLocale) void changeAppLanguage(requestedLocale);
  }, [requestedLocale]);
  const [section, setSection] = useState(
    requestedScreen === "modes"
      ? "Modes"
      : requestedScreen === "dictionary"
        ? "Dictionary"
        : "Home",
  );
  if (requestedScreen === "welcome") {
    return (
      <>
        <OnboardingProgress current={1} />
        <WelcomeOnboarding onComplete={() => undefined} />
      </>
    );
  }
  return (
    <div className="product-shell select-none cursor-default">
      <div className="product-shell-main">
        <aside className="product-sidebar">
          <div className="sidebar-brand">
            <PressayWordmark width={118} />
            <span className="beta-label">BETA</span>
          </div>
          <label className="sidebar-search">
            <Search width={14} height={14} aria-hidden="true" />
            <input placeholder="Search settings" aria-label="Search settings" />
            <kbd>⌘K</kbd>
          </label>
          <nav className="sidebar-navigation" aria-label="Primary">
            {PREVIEW_SECTIONS.map(({ id, label, icon: Icon, group }, index) => {
              const active = section === label;
              const startsGroup =
                index > 0 && PREVIEW_SECTIONS[index - 1]?.group !== group;
              return (
                <div key={id}>
                  {startsGroup ? (
                    <div className="sidebar-divider" aria-hidden="true" />
                  ) : null}
                  <button
                    type="button"
                    className={`sidebar-item ${active ? "is-active" : ""}`}
                    aria-current={active ? "page" : undefined}
                    onClick={() => setSection(label)}
                  >
                    <Icon width={18} height={18} />
                    <span>{label}</span>
                    {["history", "account", "postprocessing"].includes(id) ? (
                      <small
                        className={`sidebar-status-dot ${id === "postprocessing" ? "is-warning" : "is-muted"}`}
                        aria-label="Setup required"
                      />
                    ) : null}
                  </button>
                </div>
              );
            })}
          </nav>
        </aside>
        <main className="product-content">
          <PageAtmosphere
            section={
              (PREVIEW_SECTIONS.find((item) => item.label === section)?.id ??
                "home") as SidebarSection
            }
          />
          <div className="product-scroll-region">
            <div className="product-content-inner">
              {section === "Modes" ? (
                <ModesSettingsView
                  config={PREVIEW_PRODUCTIVITY}
                  onActivate={() => undefined}
                  onUseOnce={() => undefined}
                  onSaveMode={() => true}
                  onDeleteMode={() => undefined}
                  onSaveProfile={() => true}
                  onDeleteProfile={() => undefined}
                  onExport={() => undefined}
                  onImport={() => undefined}
                  routeAvailability={{
                    local: { ready: true, detail: "Nothing leaves this Mac" },
                    byok: {
                      ready: false,
                      detail: "Choose a private provider to enable this mode",
                    },
                    pressay_cloud: {
                      ready: false,
                      detail: "Connect your Pressay account first",
                    },
                  }}
                  onConfigureRoute={() => setSection("Providers")}
                />
              ) : section === "Dictionary" ? (
                <DictionarySettingsView
                  config={PREVIEW_PRODUCTIVITY}
                  onReplace={() => true}
                />
              ) : (
                <HomeDashboardView
                  pipeline={PREVIEW_PIPELINE}
                  modelName="Parakeet V3"
                  shortcut="⌥ Space"
                  microphone="MacBook Microphone"
                  correction={{
                    available: true,
                    armed: false,
                    target_app_name: "Notes",
                    expires_in_seconds: 92,
                  }}
                  onArmCorrection={() => undefined}
                  onCancelCorrection={() => undefined}
                />
              )}
            </div>
          </div>
        </main>
      </div>
      <footer className="preview-footer">
        <span>Parakeet V3</span>
        <span className="technical-label">v2.0.0-beta.1</span>
      </footer>
    </div>
  );
};
