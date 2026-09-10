import { describe, expect, test } from "bun:test";
import { formatKeyCombination } from "../src/lib/utils/keyboard";

describe("keyboard shortcut formatting", () => {
  test("uses compact native modifier symbols on macOS", () => {
    expect(formatKeyCombination("option_left+space", "macos")).toBe(
      "⌥ + Space",
    );
    expect(formatKeyCombination("command_right+shift+a", "macos")).toBe(
      "⌘ + ⇧ + A",
    );
  });

  test("keeps explicit modifier sides on other platforms", () => {
    expect(formatKeyCombination("option_left+space", "windows")).toBe(
      "Left Option + Space",
    );
  });
});
