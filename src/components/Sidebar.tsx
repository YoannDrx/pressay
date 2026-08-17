import React from "react";
import { useTranslation } from "react-i18next";
import {
  Cog,
  BookOpen,
  FlaskConical,
  History,
  House,
  Info,
  Sparkles,
  Cpu,
  Layers3,
  UserRound,
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
  DictionarySettings,
  ModesSettings,
  AccountSettings,
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
  labelDefault: string;
  icon: React.ComponentType<IconProps>;
  component: React.ComponentType;
  enabled: (settings: any) => boolean;
  group: "primary" | "secondary";
}

export const SECTIONS_CONFIG = {
  home: {
    labelKey: "sidebar.home",
    labelDefault: "Home",
    icon: House,
    component: HomeDashboard,
    enabled: () => true,
    group: "primary",
  },
  modes: {
    labelKey: "pressay.sidebar.modes",
    labelDefault: "Modes",
    icon: Layers3,
    component: ModesSettings,
    enabled: () => true,
    group: "primary",
  },
  dictionary: {
    labelKey: "pressay.sidebar.dictionary",
    labelDefault: "Dictionary",
    icon: BookOpen,
    component: DictionarySettings,
    enabled: () => true,
    group: "primary",
  },
  general: {
    labelKey: "pressay.sidebar.settings",
    labelDefault: "Settings",
    icon: PressayMark,
    component: GeneralSettings,
    enabled: () => true,
    group: "primary",
  },
  history: {
    labelKey: "sidebar.history",
    labelDefault: "History",
    icon: History,
    component: HistorySettings,
    enabled: (settings) => settings?.history_enabled ?? false,
    group: "primary",
  },
  account: {
    labelKey: "sidebar.account",
    labelDefault: "Account",
    icon: UserRound,
    component: AccountSettings,
    enabled: () => true,
    group: "primary",
  },
  models: {
    labelKey: "sidebar.models",
    labelDefault: "Models",
    icon: Cpu,
    component: ModelsSettings,
    enabled: () => true,
    group: "secondary",
  },
  advanced: {
    labelKey: "sidebar.advanced",
    labelDefault: "Advanced",
    icon: Cog,
    component: AdvancedSettings,
    enabled: () => true,
    group: "secondary",
  },
  postprocessing: {
    labelKey: "sidebar.postProcessing",
    labelDefault: "Providers",
    icon: Sparkles,
    component: PostProcessingSettings,
    enabled: (settings) => settings?.post_process_enabled ?? false,
    group: "secondary",
  },
  debug: {
    labelKey: "sidebar.debug",
    labelDefault: "Debug",
    icon: FlaskConical,
    component: DebugSettings,
    enabled: (settings) =>
      import.meta.env.DEV && (settings?.debug_mode ?? false),
    group: "secondary",
  },
  about: {
    labelKey: "sidebar.about",
    labelDefault: "About",
    icon: Info,
    component: AboutSettings,
    enabled: () => true,
    group: "secondary",
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
        {availableSections.map((section, index) => {
          const Icon = section.icon;
          const isActive = activeSection === section.id;
          const startsSecondary =
            section.group === "secondary" &&
            availableSections[index - 1]?.group !== "secondary";

          return (
            <React.Fragment key={section.id}>
              {startsSecondary ? (
                <div className="sidebar-divider" aria-hidden="true" />
              ) : null}
              <button
                type="button"
                className={`sidebar-item ${isActive ? "is-active" : ""}`}
                onClick={() => onSectionChange(section.id)}
                aria-current={isActive ? "page" : undefined}
              >
                <Icon width={18} height={18} className="shrink-0" />
                <span
                  className="truncate"
                  title={t(section.labelKey, {
                    defaultValue: section.labelDefault,
                  })}
                >
                  {t(section.labelKey, {
                    defaultValue: section.labelDefault,
                  })}
                </span>
              </button>
            </React.Fragment>
          );
        })}
      </nav>
    </aside>
  );
};
