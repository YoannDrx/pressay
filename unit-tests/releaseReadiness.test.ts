import { describe, expect, it } from "bun:test";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { validateReleaseReadiness } from "../scripts/voice-os/release-readiness";

function fixture(status: "pass" | "blocked") {
  const root = mkdtempSync(join(tmpdir(), "pressay-release-readiness-"));
  mkdirSync(join(root, "src-tauri"), { recursive: true });
  mkdirSync(join(root, "docs/voice-os"), { recursive: true });
  writeFileSync(
    join(root, "package.json"),
    JSON.stringify({ version: "2.0.0-beta.5" }),
  );
  writeFileSync(
    join(root, "src-tauri/tauri.conf.json"),
    JSON.stringify({
      version: "2.0.0-beta.5",
      identifier: "app.pressay.desktop",
    }),
  );
  writeFileSync(
    join(root, "src-tauri/tauri.appstore.conf.json"),
    JSON.stringify({ version: "2.0.0", identifier: "fr.yodev.pressay" }),
  );
  writeFileSync(
    join(root, "src-tauri/Cargo.toml"),
    '[package]\nname = "pressay"\nversion = "2.0.0-beta.5"\n',
  );
  writeFileSync(
    join(root, "docs/voice-os/release-gates.json"),
    JSON.stringify({
      auditedAt: "2026-08-25",
      sourceCommits: {
        desktop: "a".repeat(40),
        cloud: "b".repeat(40),
        web: "c".repeat(40),
      },
      gates: [
        {
          id: "candidate",
          channels: ["direct"],
          status,
          stage: "preflight",
          evidence: status === "pass" ? ["fixture"] : [],
          notes: "Fixture gate",
        },
      ],
    }),
  );
  return root;
}

describe("release readiness", () => {
  it("reports open gates without failing a prerelease preflight", () => {
    expect(
      validateReleaseReadiness(fixture("blocked"), "direct", false).open,
    ).toEqual([{ id: "candidate", status: "blocked", notes: "Fixture gate" }]);
  });

  it("fails a strict commercial release while any gate is open", () => {
    expect(() =>
      validateReleaseReadiness(fixture("blocked"), "direct", true),
    ).toThrow("direct release preflight is blocked by: candidate");
  });

  it("accepts a strict release only when every channel gate has evidence", () => {
    expect(
      validateReleaseReadiness(fixture("pass"), "direct", true).passed,
    ).toEqual(["candidate"]);
  });

  it("can require a pre-upload gate without requiring later launch gates", () => {
    expect(() =>
      validateReleaseReadiness(fixture("blocked"), "direct", false, [
        "candidate",
      ]),
    ).toThrow("direct operation is blocked by: candidate");
  });
});
