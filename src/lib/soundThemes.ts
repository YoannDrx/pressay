import type { SoundTheme } from "@/bindings";

export const BUNDLED_SOUND_THEME_LABELS: Record<
  Exclude<SoundTheme, "custom">,
  string
> = {
  marimba: "Marimba",
  pop: "Pop",
  minimal: "Minimal",
  soft: "Soft",
  glass: "Glass",
  mechanical: "Mechanical",
  dreamy: "Dreamy",
  scifi: "Sci-Fi",
  studio: "Studio",
  zen: "Zen",
};
