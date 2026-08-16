import React from "react";
import { useTranslation } from "react-i18next";
import {
  Cog,
  FlaskConical,
  History,
  House,
  Info,
  Sparkles,
  Cpu,
} from "lucide-react";
import PressayWordmark from "./icons/PressayWordmark";
import PressayMark from "./icons/PressayMark";
import { useSettings } from "../hooks/useSettings";
import {
  GeneralSettings,
  AdvancedSettings,
  HistorySettings,
  DebugSettings,
  AboutSettings,
  PostProcessingSettings,
  ModelsSettings,
} from "./settings";
import { HomeDashboard } from "./dashboard/HomeDashboard";

export type SidebarSection = keyof typeof SECTIONS_CONFIG;

interface IconProps {
  width?: number | string;
  height?: number | string;
  size?: number | string;
  className?: string;
  [key: string]: any;
}

interface SectionConfig {
  labelKey: string;
  icon: React.ComponentType<IconProps>;
  component: React.ComponentType;
  enabled: (settings: any) => boolean;
}

export const SECTIONS_CONFIG = {
  home: {
    labelKey: "sidebar.home",
    icon: House,
    component: HomeDashboard,
    enabled: () => true,
  },
  general: {
    labelKey: "sidebar.general",
    icon: PressayMark,
    component: GeneralSettings,
    enabled: () => true,
  },
  history: {
    labelKey: "sidebar.history",
    icon: History,
    component: HistorySettings,
    enabled: (settings) => settings?.history_enabled ?? false,
  },
  models: {
    labelKey: "sidebar.models",
    icon: Cpu,
    component: ModelsSettings,
    enabled: () => true,
  },
  advanced: {
    labelKey: "sidebar.advanced",
    icon: Cog,
    component: AdvancedSettings,
    enabled: () => true,
  },
  postprocessing: {
    labelKey: "sidebar.postProcessing",
    icon: Sparkles,
    component: PostProcessingSettings,
    enabled: (settings) => settings?.post_process_enabled ?? false,
  },
  debug: {
    labelKey: "sidebar.debug",
    icon: FlaskConical,
    component: DebugSettings,
    enabled: (settings) =>
      import.meta.env.DEV && (settings?.debug_mode ?? false),
  },
  about: {
    labelKey: "sidebar.about",
    icon: Info,
    component: AboutSettings,
    enabled: () => true,
  },
} as const satisfies Record<string, SectionConfig>;

interface SidebarProps {
  activeSection: SidebarSection;
  onSectionChange: (section: SidebarSection) => void;
}

export const Sidebar: React.FC<SidebarProps> = ({
  activeSection,
  onSectionChange,
}) => {
  const { t } = useTranslation();
  const { settings } = useSettings();

  const availableSections = Object.entries(SECTIONS_CONFIG)
    .filter(([_, config]) => config.enabled(settings))
    .map(([id, config]) => ({ id: id as SidebarSection, ...config }));

  return (
    <aside className="product-sidebar">
      <div className="sidebar-brand">
        <PressayWordmark width={118} />
        <span className="beta-label">BETA</span>
      </div>
      <nav className="sidebar-navigation" aria-label="Primary">
        {availableSections.map((section) => {
          const Icon = section.icon;
          const isActive = activeSection === section.id;

          return (
            <button
              type="button"
              key={section.id}
              className={`sidebar-item ${isActive ? "is-active" : ""}`}
              onClick={() => onSectionChange(section.id)}
              aria-current={isActive ? "page" : undefined}
            >
              <Icon width={18} height={18} className="shrink-0" />
              <span className="truncate" title={t(section.labelKey)}>
                {t(section.labelKey)}
              </span>
            </button>
          );
        })}
      </nav>
    </aside>
  );
};
