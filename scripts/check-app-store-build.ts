import assert from "node:assert/strict";

// 2.0.3 reached Apple; 2.0.4 was packaged but refused for export compliance.
// Reserve both numbers to keep archived evidence unambiguous.
export const RESERVED_BUILD = "2.0.4";

function components(version: string): number[] {
  assert.match(
    version,
    /^[1-9]\d{0,3}(?:\.(?:0|[1-9]\d?)){0,2}$/,
    "Use a release build number such as 2.0.5 (at most 9999.99.99)",
  );
  const parts = version.split(".").map(Number);
  return [parts[0], parts[1] ?? 0, parts[2] ?? 0];
}

function compare(left: number[], right: number[]): number {
  for (let i = 0; i < 3; i++) {
    if (left[i] !== right[i]) return left[i] - right[i];
  }
  return 0;
}

/** Validate against the highest build observed in Apple, across public versions. */
export function checkAppStoreBuild(build: string, previous: string): void {
  const candidate = components(build);
  const latest = components(previous);
  assert(
    compare(latest, components("2.0.3")) >= 0,
    "Previous build predates the known Apple upload 2.0.3; refresh App Store Connect",
  );
  assert(
    compare(candidate, components(RESERVED_BUILD)) > 0,
    `Build must exceed reserved candidate ${RESERVED_BUILD}`,
  );
  assert(
    compare(candidate, latest) > 0,
    "Build must exceed the highest App Store Connect build, including other public versions",
  );
}

if (import.meta.main) {
  const [build, previous, ...extra] = process.argv.slice(2);
  assert(
    build && previous && extra.length === 0,
    "Usage: bun scripts/check-app-store-build.ts <build> <highest-Apple-build>",
  );
  checkAppStoreBuild(build, previous);
  console.log(
    `App Store build ${build} exceeds ${previous} and reserved archives.`,
  );
}
