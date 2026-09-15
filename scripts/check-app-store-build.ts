import assert from "node:assert/strict";

// 2.0.3 reached Apple; 2.0.4 was packaged but refused for export compliance.
// Reserve both numbers to keep archived evidence unambiguous.
export const RESERVED_BUILD = "2.0.4";
// Verified in TestFlight on 2026-09-15, under the older public version 1.2.0.
export const HIGHEST_KNOWN_APPLE_BUILD = "12001";

function components(version: string): bigint[] {
  assert.equal(
    version,
    version.trim(),
    "Build numbers cannot contain whitespace",
  );
  assert.match(
    version,
    /^[1-9]\d*(?:\.(?:0|[1-9]\d*)){0,2}$/,
    "Use one to three numeric release components, such as 12002",
  );
  const parts = version.split(".").map(BigInt);
  return [parts[0], parts[1] ?? 0n, parts[2] ?? 0n];
}

function compare(left: bigint[], right: bigint[]): number {
  for (let i = 0; i < 3; i++) {
    if (left[i] !== right[i]) return left[i] > right[i] ? 1 : -1;
  }
  return 0;
}

/** Validate against the highest build observed in Apple, across public versions. */
export function checkAppStoreBuild(build: string, previous: string): void {
  const candidate = components(build);
  const latest = components(previous);
  assert(
    compare(latest, components(HIGHEST_KNOWN_APPLE_BUILD)) >= 0,
    `Previous build predates the known Apple upload ${HIGHEST_KNOWN_APPLE_BUILD}; refresh App Store Connect across all public versions`,
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
