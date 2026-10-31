import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// App Review 3.1.1: the Mac App Store build buys through StoreKit only. The
// web checkout ("Upgrade to Pro" in Direct builds) exists only behind the
// `stripe-purchases` Cargo feature, so these checks pin the feature graph and
// the release workflows that select it.

const root = join(import.meta.dir, "..");
const read = (path: string) => readFileSync(join(root, path), "utf8");

type CargoManifest = { features: Record<string, string[]> };
const cargo = Bun.TOML.parse(read("src-tauri/Cargo.toml")) as CargoManifest;

/** Every feature a selection turns on, transitively. */
function closure(selected: string[]): Set<string> {
  const enabled = new Set<string>();
  const visit = (feature: string) => {
    if (enabled.has(feature)) return;
    enabled.add(feature);
    for (const implied of cargo.features[feature] ?? []) {
      if (!implied.includes("/") && !implied.startsWith("dep:")) visit(implied);
    }
  };
  selected.forEach(visit);
  return enabled;
}

/** The `--features` values a workflow passes to cargo or tauri. */
function workflowFeatureSets(path: string): string[][] {
  return [
    ...read(path).matchAll(
      /--features[ =]+([A-Za-z0-9_,${}.\- ]+?)(?:\s|"|$)/g,
    ),
  ]
    .map((match) => match[1].split(",").map((name) => name.trim()))
    .filter((names) => names.every((name) => /^[a-z-]+$/.test(name)));
}

describe("web checkout and the Mac App Store build", () => {
  test("stripe-purchases implies the Direct channel and enforced entitlements", () => {
    const enabled = closure(["stripe-purchases"]);
    expect(enabled.has("direct")).toBe(true);
    expect(enabled.has("commercial-entitlements")).toBe(true);
    expect(enabled.has("mas")).toBe(false);
  });

  test("no Store feature selection can reach the web checkout", () => {
    for (const store of [["mas"], ["storekit-purchases"]]) {
      const enabled = closure(store);
      expect(enabled.has("mas")).toBe(true);
      expect(enabled.has("stripe-purchases")).toBe(false);
      expect(enabled.has("direct")).toBe(false);
    }
  });

  test("the crate refuses to compile a Store build with the web checkout", () => {
    const lib = read("src-tauri/src/lib.rs");
    expect(lib).toContain('#[cfg(all(feature = "mas", feature = "direct"))]');
    expect(lib).toContain(
      '#[cfg(all(feature = "mas", feature = "stripe-purchases"))]',
    );
  });

  test("App Store workflows never select a Direct or checkout feature", () => {
    for (const path of [
      ".github/workflows/app-store-release.yml",
      ".github/workflows/app-store-spike.yml",
    ]) {
      const sets = workflowFeatureSets(path);
      expect(sets.length).toBeGreaterThan(0);
      for (const features of sets) {
        const enabled = closure(features);
        expect(enabled.has("mas")).toBe(true);
        expect(enabled.has("stripe-purchases")).toBe(false);
        expect(enabled.has("direct")).toBe(false);
      }
    }
  });

  test("stable DMG and Windows releases sell Pro through the web checkout", () => {
    const release = read(".github/workflows/release.yml");
    expect(release).toContain(
      'echo "features=updater,stripe-purchases" >> "$GITHUB_OUTPUT"',
    );
    // Prereleases enforce nothing, so they offer no purchase.
    expect(release).toContain('echo "features=updater" >> "$GITHUB_OUTPUT"');
    expect(release).not.toMatch(/features=[^"\n]*\bmas\b/);
  });
});
