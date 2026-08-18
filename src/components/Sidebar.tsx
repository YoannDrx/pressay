import React, { useEffect, useMemo, useRef, useState } from "react";
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
  Search,
  AudioWaveform,
} from "lucide-react";
import PressayWordmark from "./icons/PressayWordmark";
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
  group: "primary" | "system" | "secondary";
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
    icon: AudioWaveform,
    component: GeneralSettings,
    enabled: () => true,
    group: "system",
  },
  history: {
    labelKey: "sidebar.history",
    labelDefault: "History",
    icon: History,
    component: HistorySettings,
    enabled: () => true,
    group: "primary",
  },
  account: {
    labelKey: "sidebar.account",
    labelDefault: "Account",
    icon: UserRound,
    component: AccountSettings,
    enabled: () => true,
    group: "system",
  },
  models: {
    labelKey: "sidebar.models",
    labelDefault: "Models",
    icon: Cpu,
    component: ModelsSettings,
    enabled: () => true,
    group: "system",
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
    enabled: () => true,
    group: "system",
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

const SECTION_ORDER: SidebarSection[] = [
  "home",
  "modes",
  "dictionary",
  "history",
  "general",
  "models",
  "postprocessing",
  "account",
  "advanced",
  "about",
  "debug",
];

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
  const [query, setQuery] = useState("");
  const searchRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const focusSearch = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        searchRef.current?.focus();
      }
    };
    window.addEventListener("keydown", focusSearch);
    return () => window.removeEventListener("keydown", focusSearch);
  }, []);

  const availableSections = useMemo(() => {
    const normalizedQuery = query.trim().toLocaleLowerCase();
    return Object.entries(SECTIONS_CONFIG)
      .filter(([_, config]) => config.enabled(settings))
      .map(([id, config]) => ({ id: id as SidebarSection, ...config }))
      .filter((section) => {
        if (!normalizedQuery) return true;
        return t(section.labelKey, { defaultValue: section.labelDefault })
          .toLocaleLowerCase()
          .includes(normalizedQuery);
      })
      .sort(
        (left, right) =>
          SECTION_ORDER.indexOf(left.id) - SECTION_ORDER.indexOf(right.id),
      );
  }, [query, settings, t]);

  const sectionStatus = (section: SidebarSection) => {
    if (section === "history" && !settings?.history_enabled) {
      return { label: t("pressay.sidebar.status.off"), tone: "muted" };
    }
    if (section === "postprocessing") {
      const providerId = settings?.post_process_provider_id;
      const configured = providerId
        ? providerId === "apple_intelligence" ||
          Boolean(
            settings?.post_process_models?.[providerId] &&
            (providerId === "custom" ||
              settings?.post_process_api_keys_configured?.[providerId]),
          )
        : false;
      if (!configured) {
        return { label: t("pressay.sidebar.status.setup"), tone: "warning" };
      }
    }
    if (section === "account" && !settings?.pressay_cloud_account_id) {
      return {
        label: t("pressay.sidebar.status.offline"),
        tone: "muted",
      };
    }
    return null;
  };

  return (
    <aside className="product-sidebar">
      <div className="sidebar-brand">
        <PressayWordmark width={118} />
        <span className="beta-label">BETA</span>
      </div>
      <label className="sidebar-search">
        <Search width={14} height={14} aria-hidden="true" />
        <input
          ref={searchRef}
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder={t("pressay.sidebar.search")}
          aria-label={t("pressay.sidebar.search")}
        />
        <kbd>{t("pressay.sidebar.searchShortcut")}</kbd>
      </label>
      <nav
        className="sidebar-navigation"
        aria-label={t("pressay.sidebar.navigation")}
      >
        {availableSections.map((section, index) => {
          const Icon = section.icon;
          const isActive = activeSection === section.id;
          const status = sectionStatus(section.id);
          const startsGroup =
            index > 0 && availableSections[index - 1]?.group !== section.group;

          return (
            <React.Fragment key={section.id}>
              {startsGroup ? (
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
                {status ? (
                  <small
                    className={`sidebar-status-dot is-${status.tone}`}
                    aria-label={status.label}
                    title={status.label}
                  />
                ) : null}
              </button>
            </React.Fragment>
          );
        })}
        {availableSections.length === 0 ? (
          <p className="sidebar-empty">{t("pressay.sidebar.noResults")}</p>
        ) : null}
      </nav>
    </aside>
  );
};
