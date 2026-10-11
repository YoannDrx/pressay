import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * One source version must reach Cargo (CARGO_PKG_VERSION, used by build.rs and
 * the entitlement verifier), npm, the Tauri bundle and every per-channel Tauri
 * override. A stable commercial environment additionally refuses pre-release
 * versions, mirroring the build.rs gate before a macOS runner is even started.
 */

export type VersionSources = Record<string, string>;

type BuildEnvironment = { id: string; channel: string };

const ROOT = join(import.meta.dir, "..");

function readJson(path: string): Record<string, unknown> {
  return JSON.parse(readFileSync(join(ROOT, path), "utf8"));
}

function cargoPackageVersion(toml: string): string {
  const match = toml.match(/^\[package\][\s\S]*?^version\s*=\s*"([^"]+)"/m);
  assert(match, "src-tauri/Cargo.toml has no [package] version");
  return match[1];
}

function cargoLockVersion(lock: string, crate: string): string {
  const match = lock.match(
    new RegExp(`\\[\\[package\\]\\]\\nname = "${crate}"\\nversion = "([^"]+)"`),
  );
  assert(match, `src-tauri/Cargo.lock has no entry for ${crate}`);
  return match[1];
}

export function readVersionSources(): VersionSources {
  const cargoToml = readFileSync(join(ROOT, "src-tauri/Cargo.toml"), "utf8");
  const sources: VersionSources = {
    "src-tauri/Cargo.toml": cargoPackageVersion(cargoToml),
    "src-tauri/Cargo.lock": cargoLockVersion(
      readFileSync(join(ROOT, "src-tauri/Cargo.lock"), "utf8"),
      "pressay",
    ),
    "package.json": String(readJson("package.json").version),
    "src-tauri/tauri.conf.json": String(
      readJson("src-tauri/tauri.conf.json").version,
    ),
  };
  // Channel overrides may omit the version (inheriting the base config); when
  // present they must not disagree with the binary's own version.
  for (const override of [
    "src-tauri/tauri.appstore.conf.json",
    "src-tauri/tauri.updater.conf.json",
    "src-tauri/tauri.production-candidate.conf.json",
  ]) {
    const value = readJson(override).version;
    if (typeof value === "string") sources[override] = value;
  }
  return sources;
}

export function checkVersionsMatch(sources: VersionSources): string {
  const versions = new Set(Object.values(sources));
  assert.equal(
    versions.size,
    1,
    `Release versions disagree: ${JSON.stringify(sources)}`,
  );
  const [version] = versions;
  assert.match(
    version,
    /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/,
    "Use a semantic version such as 2.0.0 or 2.1.0-rc.1",
  );
  return version;
}

export function checkEnvironmentAcceptsVersion(
  version: string,
  environment: BuildEnvironment,
): void {
  if (environment.channel === "stable") {
    assert(
      !version.includes("-"),
      `${environment.id} is a stable commercial environment and cannot ship pre-release version ${version}`,
    );
  }
}

function findEnvironment(id: string): BuildEnvironment {
  const manifest = readJson("config/build-environments.json") as {
    environments: BuildEnvironment[];
  };
  const environment = manifest.environments.find((entry) => entry.id === id);
  assert(environment, `Unknown build environment ${id}`);
  return environment;
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  const environments: string[] = [];
  for (let index = 0; index < args.length; index++) {
    assert.equal(
      args[index],
      "--environment",
      "Usage: bun scripts/check-release-version.ts [--environment <id>]...",
    );
    const id = args[++index];
    assert(id, "--environment requires a build environment id");
    environments.push(id);
  }
  const version = checkVersionsMatch(readVersionSources());
  for (const id of environments) {
    checkEnvironmentAcceptsVersion(version, findEnvironment(id));
  }
  console.log(
    `Release version ${version} is consistent${
      environments.length ? ` and valid for ${environments.join(", ")}` : ""
    }.`,
  );
}
