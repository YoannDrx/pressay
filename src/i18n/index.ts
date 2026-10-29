import i18n from "i18next";
import { initReactI18next } from "react-i18next";
import { isTauri } from "@tauri-apps/api/core";
import { locale, platform } from "@tauri-apps/plugin-os";
import { LANGUAGE_METADATA } from "./languages";
import { commands } from "@/bindings";
import english from "./locales/en/translation.json";
import { windowsOverrides } from "./platform/windows";
import {
  getLanguageDirection,
  updateDocumentDirection,
  updateDocumentLanguage,
} from "@/lib/utils/rtl";

// Keep English in the initial bundle and split every other catalogue into an
// on-demand chunk. All catalogues remain packaged locally for offline use.
const localeModules = import.meta.glob<{ default: Record<string, unknown> }>([
  "./locales/*/translation.json",
  "!./locales/en/translation.json",
]);
const availableLanguageCodes = [
  "en",
  ...Object.keys(localeModules)
    .map((path) => path.match(/\.\/locales\/(.+)\/translation\.json/)?.[1])
    .filter((code): code is string => Boolean(code)),
];

/**
 * Only English and French have had a human translation review. The other
 * inherited catalogues stay packaged but are not offered (App Review 2.3.8:
 * a half-translated UI reads as broken). Keep in sync with
 * `reviewed_app_language` in src-tauri/src/settings.rs.
 */
export const REVIEWED_LANGUAGE_CODES = ["en", "fr"] as const;

// Build supported languages list from discovered locales + metadata
export const SUPPORTED_LANGUAGES = availableLanguageCodes
  .filter((code) =>
    (REVIEWED_LANGUAGE_CODES as readonly string[]).includes(code),
  )
  .map((code) => {
    const meta = LANGUAGE_METADATA[code];
    if (!meta) {
      console.warn(`Missing metadata for locale "${code}" in languages.ts`);
      return { code, name: code, nativeName: code, priority: undefined };
    }
    return {
      code,
      name: meta.name,
      nativeName: meta.nativeName,
      priority: meta.priority,
    };
  })
  .sort((a, b) => {
    // Sort by priority first (lower = higher), then alphabetically
    if (a.priority !== undefined && b.priority !== undefined) {
      return a.priority - b.priority;
    }
    if (a.priority !== undefined) return -1;
    if (b.priority !== undefined) return 1;
    return a.name.localeCompare(b.name);
  });

export type SupportedLanguageCode = string;

/** French systems get French; every other locale gets English. */
export const getSupportedLanguage = (
  langCode: string | null | undefined,
): SupportedLanguageCode | null => {
  if (!langCode) return null;
  const language = langCode.trim().toLowerCase().replace(/_/g, "-");
  return language.split("-")[0] === "fr" ? "fr" : "en";
};

// Initialize i18n with English as default
// Language will be synced from settings after init
i18n.use(initReactI18next).init({
  resources: { en: { translation: english } },
  lng: "en",
  fallbackLng: "en",
  interpolation: {
    escapeValue: false, // React already escapes values
  },
  react: {
    useSuspense: false, // Disable suspense for SSR compatibility
  },
});

const isWindows = isTauri() && platform() === "windows";

/** Swap Mac wording for Windows wording on top of a loaded catalogue. */
const applyPlatformOverrides = (langCode: string) => {
  const overrides = isWindows ? windowsOverrides[langCode] : undefined;
  if (overrides)
    i18n.addResourceBundle(langCode, "translation", overrides, true, true);
};

applyPlatformOverrides("en");

const loadLanguage = async (langCode: string) => {
  if (i18n.hasResourceBundle(langCode, "translation")) return;
  const loader = localeModules[`./locales/${langCode}/translation.json`];
  if (!loader) return;
  const module = await loader();
  i18n.addResourceBundle(langCode, "translation", module.default, true, true);
  applyPlatformOverrides(langCode);
};

export const changeAppLanguage = async (langCode: string) => {
  const supported = getSupportedLanguage(langCode) || "en";
  await loadLanguage(supported);
  await i18n.changeLanguage(supported);
};

// Sync language from app settings
export const syncLanguageFromSettings = async () => {
  try {
    const result = await commands.getAppSettings();
    if (result.status === "ok" && result.data.app_language) {
      const supported = getSupportedLanguage(result.data.app_language);
      if (supported && supported !== i18n.language) {
        await changeAppLanguage(supported);
      }
    } else {
      // Fall back to system locale detection if no saved preference
      const systemLocale = await locale();
      const supported = getSupportedLanguage(systemLocale);
      if (supported && supported !== i18n.language) {
        await changeAppLanguage(supported);
      }
    }
  } catch (e) {
    console.warn("Failed to sync language from settings:", e);
  }
};

// Run language sync on init
if (isTauri()) {
  syncLanguageFromSettings();
}

// Listen for language changes to update HTML dir and lang attributes
i18n.on("languageChanged", (lng) => {
  const dir = getLanguageDirection(lng);
  updateDocumentDirection(dir);
  updateDocumentLanguage(lng);
});

// Re-export RTL utilities for convenience
export { getLanguageDirection, isRTLLanguage } from "@/lib/utils/rtl";

export default i18n;
