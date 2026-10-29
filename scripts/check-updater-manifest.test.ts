import { expect, test } from "bun:test";
import { checkUpdaterManifest } from "./check-updater-manifest";
const manifest = () => ({
  version: "2.0.0",
  platforms: {
    "darwin-aarch64": {
      url: "https://github.com/YoannDrx/pressay/releases/download/v2.0.0/Pressay.app.tar.gz",
      signature: Buffer.from(
        `untrusted comment: synthetic test\n${Buffer.alloc(74).toString("base64")}\ntrusted comment: synthetic test\n${Buffer.alloc(64).toString("base64")}\n`,
      ).toString("base64"),
    },
  },
});
test("accepts a structurally complete macOS release", () => {
  expect(() => checkUpdaterManifest(manifest(), "2.0.0")).not.toThrow();
});
test("rejects a DMG, unsigned payload, wrong host and mismatched version", () => {
  for (const url of [
    "https://evil.invalid/Pressay.app.tar.gz",
    "https://github.com/YoannDrx/pressay/releases/download/v2.0.0/Pressay.dmg",
    "https://github.com/YoannDrx/pressay/releases/download/v1.0.0/Pressay.app.tar.gz",
  ]) {
    const value = manifest();
    value.platforms["darwin-aarch64"].url = url;
    expect(() => checkUpdaterManifest(value, "2.0.0")).toThrow();
  }
  const value = manifest();
  value.platforms["darwin-aarch64"].signature = "";
  expect(() => checkUpdaterManifest(value, "2.0.0")).toThrow();
  expect(() => checkUpdaterManifest(manifest(), "2.0.1")).toThrow();
});

test("requires signed Windows installers when Windows ships", () => {
  const signature = manifest().platforms["darwin-aarch64"].signature;
  const base = "https://github.com/YoannDrx/pressay/releases/download/v2.0.0";
  const value = {
    ...manifest(),
    platforms: {
      ...manifest().platforms,
      "windows-x86_64": {
        url: `${base}/Pressay_2.0.0_x64-setup.exe`,
        signature,
      },
      "windows-aarch64": {
        url: `${base}/Pressay_2.0.0_arm64-setup.exe`,
        signature,
      },
    },
  };
  expect(() =>
    checkUpdaterManifest(value, "2.0.0", { requireWindows: true }),
  ).not.toThrow();
  expect(() =>
    checkUpdaterManifest(manifest(), "2.0.0", { requireWindows: true }),
  ).toThrow();
  value.platforms["windows-x86_64"].url = `${base}/Pressay_2.0.0_x64_en-US.msi`;
  expect(() =>
    checkUpdaterManifest(value, "2.0.0", { requireWindows: true }),
  ).toThrow();
});
