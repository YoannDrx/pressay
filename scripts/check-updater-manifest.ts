import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

/** Structural release gate; Tauri verifies the actual archive signature on install. */
export function checkUpdaterManifest(
  value: unknown,
  version: string,
  options: { requireWindows?: boolean } = {},
) {
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
  checkPlatform(platforms, "darwin-aarch64", version, ".app.tar.gz");
  if (options.requireWindows) {
    // NSIS installers double as Tauri's Windows update payload.
    checkPlatform(platforms, "windows-x86_64", version, "-setup.exe");
    checkPlatform(platforms, "windows-aarch64", version, "-setup.exe");
  }
}

function checkPlatform(
  platforms: Record<string, { url: string; signature: string }>,
  key: string,
  version: string,
  suffix: string,
) {
  const entry = platforms[key];
  assert(entry, `Missing ${key} updater archive`);
  const url = new URL(entry.url);
  assert.equal(url.origin, "https://github.com");
  assert.equal(url.username, "");
  assert.equal(url.password, "");
  assert.equal(url.search, "");
  assert.equal(url.hash, "");
  assert(
    url.pathname.startsWith(`/YoannDrx/pressay/releases/download/v${version}/`),
  );
  assert(
    url.pathname.endsWith(suffix),
    `${key} must reference a ${suffix} update payload`,
  );
  assert.equal(typeof entry.signature, "string");
  const decoded = Buffer.from(entry.signature, "base64");
  assert.equal(
    decoded.toString("base64"),
    entry.signature.trim(),
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
  const [file, version, platformsFlag] = process.argv.slice(2);
  assert(
    file && version,
    "Usage: bun scripts/check-updater-manifest.ts <latest.json> <version> [windows]",
  );
  checkUpdaterManifest(JSON.parse(readFileSync(file, "utf8")), version, {
    requireWindows: platformsFlag === "windows",
  });
  console.log(
    "Updater metadata matches the release version and signed macOS archive format.",
  );
}
