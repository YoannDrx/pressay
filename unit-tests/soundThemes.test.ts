import { describe, expect, test } from "bun:test";
import { BUNDLED_SOUND_THEME_LABELS } from "../src/lib/soundThemes";

describe("bundled sound themes", () => {
  test("exposes the ten supported frontend/backend contract values", () => {
    expect(BUNDLED_SOUND_THEME_LABELS).toEqual({
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
    });
  });
});
