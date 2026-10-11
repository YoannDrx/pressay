import { describe, expect, test } from "bun:test";
import {
  checkEnvironmentAcceptsVersion,
  checkVersionsMatch,
  readVersionSources,
} from "../scripts/check-release-version";

describe("release version consistency", () => {
  test("the checked-in sources agree on one version", () => {
    expect(() => checkVersionsMatch(readVersionSources())).not.toThrow();
  });

  test("a disagreement between Cargo, npm and Tauri is refused", () => {
    expect(() =>
      checkVersionsMatch({
        "src-tauri/Cargo.toml": "2.0.0-rc.1",
        "package.json": "2.0.0",
      }),
    ).toThrow();
  });

  test("stable commercial environments refuse pre-release versions", () => {
    const production = { id: "production-mac-app-store", channel: "stable" };
    expect(() =>
      checkEnvironmentAcceptsVersion("2.0.0-rc.1", production),
    ).toThrow();
    expect(() =>
      checkEnvironmentAcceptsVersion("2.0.0", production),
    ).not.toThrow();
    expect(() =>
      checkEnvironmentAcceptsVersion("2.0.0-rc.1", {
        id: "staging-mac-app-store",
        channel: "beta",
      }),
    ).not.toThrow();
  });
});
