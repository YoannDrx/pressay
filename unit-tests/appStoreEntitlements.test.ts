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

describe("privacy manifest", () => {
  const manifest = readFileSync(
    join(import.meta.dir, "../src-tauri/gen/apple/PrivacyInfo.xcprivacy"),
    "utf8",
  );

  test("declares no tracking and the data the Cloud account collects", () => {
    expect(manifest).toMatch(/<key>NSPrivacyTracking<\/key>\s*<false\/>/);
    for (const kind of [
      "EmailAddress",
      "UserID",
      "DeviceID",
      "PurchaseHistory",
      "AudioData",
      "OtherUserContent",
    ]) {
      expect(manifest).toContain(`NSPrivacyCollectedDataType${kind}<`);
    }
    expect(manifest).not.toMatch(
      /NSPrivacyCollectedDataTypeTracking<\/key>\s*<true\/>/,
    );
  });

  test("declares a reason for every required-reason API the app uses", () => {
    for (const [category, reason] of [
      ["FileTimestamp", "C617.1"],
      ["DiskSpace", "85F4.1"],
      ["SystemBootTime", "35F9.1"],
      ["UserDefaults", "CA92.1"],
    ]) {
      expect(manifest).toMatch(
        new RegExp(
          `NSPrivacyAccessedAPICategory${category}</string>\\s*<key>NSPrivacyAccessedAPITypeReasons</key>\\s*<array>\\s*<string>${reason.replace(".", "\\.")}</string>`,
        ),
      );
    }
  });
});
