/* eslint-disable i18next/no-literal-string -- static browser-only visual fixture */
import { useState } from "react";
import {
  BookOpen,
  Cog,
  Cpu,
  House,
  Info,
  Layers3,
  SlidersHorizontal,
} from "lucide-react";
import type { PipelineState, ProductivityConfig } from "@/bindings";
import { HomeDashboardView } from "@/components/dashboard/HomeDashboard";
import PressayWordmark from "@/components/icons/PressayWordmark";
import { OnboardingProgress, WelcomeOnboarding } from "@/components/onboarding";
import {
  DictionarySettingsView,
  ModesSettingsView,
} from "@/components/settings/productivity";

const PREVIEW_PIPELINE: PipelineState = {
  phase: "idle",
  operation_id: 0,
  binding_id: null,
  failure: null,
};

const PREVIEW_SECTIONS = [
  { label: "Home", icon: House },
  { label: "Modes", icon: Layers3 },
  { label: "Dictionary", icon: BookOpen },
  { label: "Settings", icon: SlidersHorizontal },
  { label: "Models", icon: Cpu },
  { label: "Advanced", icon: Cog },
  { label: "About", icon: Info },
];

const PREVIEW_PRODUCTIVITY: ProductivityConfig = {
  schema_version: 1,
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
  const requestedScreen = new URLSearchParams(window.location.search).get(
    "screen",
  );
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
          <nav className="sidebar-navigation" aria-label="Primary">
            {PREVIEW_SECTIONS.map(({ label, icon: Icon }) => {
              const active = section === label;
              return (
                <button
                  type="button"
                  key={label}
                  className={`sidebar-item ${active ? "is-active" : ""}`}
                  aria-current={active ? "page" : undefined}
                  onClick={() => setSection(label)}
                >
                  <Icon width={18} height={18} />
                  <span>{label}</span>
                </button>
              );
            })}
          </nav>
        </aside>
        <main className="product-content">
          <div className="product-scroll-region">
            <div className="product-content-inner">
              {section === "Modes" ? (
                <ModesSettingsView
                  config={PREVIEW_PRODUCTIVITY}
                  onActivate={() => undefined}
                  onSaveMode={() => true}
                  onDeleteMode={() => undefined}
                  onSaveProfile={() => true}
                  onDeleteProfile={() => undefined}
                />
              ) : section === "Dictionary" ? (
                <DictionarySettingsView
                  config={PREVIEW_PRODUCTIVITY}
                  onReplace={() => true}
                />
              ) : (
                <HomeDashboardView
                  language="en"
                  pipeline={PREVIEW_PIPELINE}
                  modelName="Parakeet V3"
                  shortcut="⌥ Space"
                  microphone="MacBook Microphone"
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
