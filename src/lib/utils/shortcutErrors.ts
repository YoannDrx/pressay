import type { TFunction } from "i18next";

const CONFLICT_PREFIX = "shortcut_conflict:";

/** A user-facing message for a failed shortcut change. */
export const shortcutErrorMessage = (error: unknown, t: TFunction): string => {
  const raw = error instanceof Error ? error.message : String(error);
  const index = raw.indexOf(CONFLICT_PREFIX);
  if (index >= 0) {
    const otherId = raw.slice(index + CONFLICT_PREFIX.length).trim();
    return t("settings.general.shortcut.errors.conflict", {
      other: t(`settings.general.shortcut.bindings.${otherId}.name`, {
        defaultValue: otherId,
      }),
    });
  }
  return t("settings.general.shortcut.errors.set", { error: raw });
};
