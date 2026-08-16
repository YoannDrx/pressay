/* eslint-disable i18next/no-literal-string -- static browser-only visual fixture */
import { Cog, Cpu, History, House, Info, Sparkles } from "lucide-react";
import type { PipelineState } from "@/bindings";
import { HomeDashboardView } from "@/components/dashboard/HomeDashboard";
import PressayWordmark from "@/components/icons/PressayWordmark";
import { OnboardingProgress, WelcomeOnboarding } from "@/components/onboarding";

const PREVIEW_PIPELINE: PipelineState = {
  phase: "idle",
  operation_id: 0,
  binding_id: null,
  failure: null,
};

const PREVIEW_SECTIONS = [
  { label: "Home", icon: House, active: true },
  { label: "Models", icon: Cpu },
  { label: "Advanced", icon: Cog },
  { label: "Post Process", icon: Sparkles },
  { label: "History", icon: History },
  { label: "About", icon: Info },
];

/** Browser-only visual fixture. The production Tauri runtime never renders it. */
export const ProductPreview = () => {
  if (new URLSearchParams(window.location.search).get("screen") === "welcome") {
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
            {PREVIEW_SECTIONS.map(({ label, icon: Icon, active }) => (
              <button
                type="button"
                key={label}
                className={`sidebar-item ${active ? "is-active" : ""}`}
                aria-current={active ? "page" : undefined}
              >
                <Icon width={18} height={18} />
                <span>{label}</span>
              </button>
            ))}
          </nav>
        </aside>
        <main className="product-content">
          <div className="product-scroll-region">
            <div className="product-content-inner">
              <HomeDashboardView
                language="en"
                pipeline={PREVIEW_PIPELINE}
                modelName="Parakeet V3"
                shortcut="⌥ Space"
                microphone="MacBook Microphone"
              />
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
