import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const plist = readFileSync(
  join(import.meta.dir, "../src-tauri/Entitlements.AppStore.plist"),
  "utf8",
);

function arrayFor(key: string): string[] {
  const match = plist.match(
    new RegExp(`<key>${key}</key>\\s*<array>([\\s\\S]*?)</array>`),
  );
  if (!match) return [];
  return [...match[1].matchAll(/<string>([^<]*)<\/string>/g)].map(
    (entry) => entry[1],
  );
}

describe("Mac App Store entitlements", () => {
  test("the Keychain access group is the app's own group, never a wildcard", () => {
    // Tokens, the history key and BYOK keys live in the first access group of
    // the data-protection Keychain; a wildcard leaves it undefined.
    expect(arrayFor("keychain-access-groups")).toEqual([
      "G9WFV7HNV6.fr.yodev.pressay",
    ]);
    expect(plist).toContain("<string>G9WFV7HNV6.fr.yodev.pressay</string>");
  });
});
