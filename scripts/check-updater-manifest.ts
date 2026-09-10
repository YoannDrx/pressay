import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

/** Structural release gate; Tauri verifies the actual archive signature on install. */
export function checkUpdaterManifest(value: unknown, version: string) {
  assert.match(version, /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/);
  assert(value && typeof value === "object");
  const manifest = value as Record<string, unknown>;
  assert.equal(
    manifest.version,
    version,
    "Updater version differs from the bundle",
  );
  const platforms = manifest.platforms as Record<
    string,
    { url: string; signature: string }
  >;
  assert(
    platforms && typeof platforms === "object",
    "Missing updater platforms",
  );
  const mac = platforms["darwin-aarch64"];
  assert(mac, "Missing Apple Silicon updater archive");
  const url = new URL(mac.url);
  assert.equal(url.origin, "https://github.com");
  assert.equal(url.username, "");
  assert.equal(url.password, "");
  assert.equal(url.search, "");
  assert.equal(url.hash, "");
  assert(
    url.pathname.startsWith(`/YoannDrx/pressay/releases/download/v${version}/`),
  );
  assert(
    url.pathname.endsWith(".app.tar.gz"),
    "Updater must reference an app archive, not a DMG",
  );
  assert.equal(typeof mac.signature, "string");
  const decoded = Buffer.from(mac.signature, "base64");
  assert.equal(
    decoded.toString("base64"),
    mac.signature.trim(),
    "Invalid signature encoding",
  );
  const lines = decoded.toString("utf8").trim().split(/\r?\n/);
  assert.equal(lines.length, 4, "Missing minisign signature");
  assert(lines[0].startsWith("untrusted comment:"));
  assert.equal(Buffer.from(lines[1], "base64").length, 74);
  assert(lines[2].startsWith("trusted comment:"));
  assert.equal(Buffer.from(lines[3], "base64").length, 64);
}

if (import.meta.main) {
  const [file, version] = process.argv.slice(2);
  assert(
    file && version,
    "Usage: bun scripts/check-updater-manifest.ts <latest.json> <version>",
  );
  checkUpdaterManifest(JSON.parse(readFileSync(file, "utf8")), version);
  console.log(
    "Updater metadata matches the release version and signed macOS archive format.",
  );
}
