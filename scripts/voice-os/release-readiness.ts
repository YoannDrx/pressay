import { readFileSync } from "node:fs";
import { resolve } from "node:path";

type ReleaseChannel = "direct" | "mas";
type GateStatus = "pass" | "blocked" | "external_gate";
type GateStage = "preflight" | "artifact" | "submission" | "post_release";

interface ReleaseGate {
  id: string;
  channels: ReleaseChannel[];
  status: GateStatus;
  stage: GateStage;
  evidence: string[];
  notes: string;
}

interface ReleaseGateRegistry {
  auditedAt: string;
  sourceCommits: Record<"desktop" | "cloud" | "web", string>;
  gates: ReleaseGate[];
}

export interface ReadinessReport {
  channel: ReleaseChannel;
  strict: boolean;
  directVersion: string;
  storeVersion: string;
  passed: string[];
  open: Array<{ id: string; status: GateStatus; notes: string }>;
}

function parseCargoVersion(cargoManifest: string): string {
  const packageSection = cargoManifest.match(
    /\[package\]([\s\S]*?)(?:\n\[|$)/,
  )?.[1];
  const version = packageSection?.match(/^version\s*=\s*"([^"]+)"/m)?.[1];
  if (!version)
    throw new Error("Unable to read the desktop version from Cargo.toml");
  return version;
}

function invariant(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

export function validateReleaseReadiness(
  repositoryRoot: string,
  channel: ReleaseChannel,
  strict: boolean,
  requiredGateIds: string[] = [],
): ReadinessReport {
  const readJson = <T>(path: string): T =>
    JSON.parse(readFileSync(resolve(repositoryRoot, path), "utf8")) as T;
  const packageManifest = readJson<{ version: string }>("package.json");
  const tauriManifest = readJson<{ version: string; identifier: string }>(
    "src-tauri/tauri.conf.json",
  );
  const storeManifest = readJson<{ version: string; identifier: string }>(
    "src-tauri/tauri.appstore.conf.json",
  );
  const cargoVersion = parseCargoVersion(
    readFileSync(resolve(repositoryRoot, "src-tauri/Cargo.toml"), "utf8"),
  );
  const registry = readJson<ReleaseGateRegistry>(
    "docs/voice-os/release-gates.json",
  );

  invariant(
    packageManifest.version === tauriManifest.version &&
      packageManifest.version === cargoVersion,
    "Direct release versions must match in package.json, Tauri and Cargo",
  );
  invariant(
    storeManifest.version === packageManifest.version.split("-")[0],
    "The Mac App Store version must match the stable base of the Direct version",
  );
  invariant(
    tauriManifest.identifier === "app.pressay.desktop",
    "Unexpected Direct bundle identifier",
  );
  invariant(
    storeManifest.identifier === "fr.yodev.pressay",
    "Unexpected Mac App Store bundle identifier",
  );
  invariant(
    /^20\d{2}-\d{2}-\d{2}$/.test(registry.auditedAt),
    "Invalid audit date",
  );
  for (const [repository, commit] of Object.entries(registry.sourceCommits)) {
    invariant(
      /^[0-9a-f]{40}$/.test(commit),
      `Invalid ${repository} source commit in the release registry`,
    );
  }

  const ids = new Set<string>();
  const relevant = registry.gates.filter((gate) =>
    gate.channels.includes(channel),
  );
  for (const gate of registry.gates) {
    invariant(!ids.has(gate.id), `Duplicate release gate: ${gate.id}`);
    ids.add(gate.id);
    invariant(
      gate.channels.length > 0,
      `Release gate ${gate.id} has no channel`,
    );
    invariant(
      gate.notes.trim().length > 0,
      `Release gate ${gate.id} needs notes`,
    );
    if (gate.status === "pass") {
      invariant(
        gate.evidence.length > 0,
        `Passing release gate ${gate.id} must reference evidence`,
      );
    }
  }
  invariant(
    relevant.length > 0,
    `No release gates are registered for ${channel}`,
  );

  const open = relevant
    .filter((gate) => gate.status !== "pass")
    .map(({ id, status, notes }) => ({ id, status, notes }));
  const missingRequired = requiredGateIds.filter(
    (requiredId) =>
      !relevant.some(
        (gate) => gate.id === requiredId && gate.status === "pass",
      ),
  );
  if (missingRequired.length > 0) {
    throw new Error(
      `${channel} operation is blocked by: ${missingRequired.join(", ")}`,
    );
  }
  const blockingPreflight = relevant.filter(
    (gate) => gate.stage === "preflight" && gate.status !== "pass",
  );
  if (strict && blockingPreflight.length > 0) {
    throw new Error(
      `${channel} release preflight is blocked by: ${blockingPreflight.map((gate) => gate.id).join(", ")}`,
    );
  }

  return {
    channel,
    strict,
    directVersion: packageManifest.version,
    storeVersion: storeManifest.version,
    passed: relevant
      .filter((gate) => gate.status === "pass")
      .map((gate) => gate.id),
    open,
  };
}

if (import.meta.main) {
  const channelArgument = process.argv.indexOf("--channel");
  const channel = process.argv[channelArgument + 1];
  invariant(
    channel === "direct" || channel === "mas",
    "Use --channel direct|mas",
  );
  const requiredArgument = process.argv.indexOf("--require");
  const requiredGateIds =
    requiredArgument === -1
      ? []
      : (process.argv[requiredArgument + 1] ?? "")
          .split(",")
          .map((value) => value.trim())
          .filter(Boolean);
  const report = validateReleaseReadiness(
    process.cwd(),
    channel,
    process.argv.includes("--strict"),
    requiredGateIds,
  );
  console.log(JSON.stringify(report, null, 2));
}
