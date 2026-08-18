import { existsSync } from "node:fs";

type CommandResult = { ok: boolean; value: string | null };

function run(command: string, args: string[]): CommandResult {
  const result = Bun.spawnSync([command, ...args], {
    stdout: "pipe",
    stderr: "pipe",
  });
  return {
    ok: result.exitCode === 0,
    value:
      result.exitCode === 0 ? result.stdout.toString().trim() || null : null,
  };
}

const targetApplications = {
  Mail: "/System/Applications/Mail.app",
  Messages: "/System/Applications/Messages.app",
  Notes: "/System/Applications/Notes.app",
  Safari: "/Applications/Safari.app",
  Chrome: "/Applications/Google Chrome.app",
  Slack: "/Applications/Slack.app",
  Notion: "/Applications/Notion.app",
  Word: "/Applications/Microsoft Word.app",
  Cursor: "/Applications/Cursor.app",
  Terminal: "/System/Applications/Utilities/Terminal.app",
} as const;

const disk = run("df", ["-k", "."]);
const diskFields = disk.value?.split("\n").at(-1)?.trim().split(/\s+/);
const applications = Object.fromEntries(
  Object.entries(targetApplications).map(([name, path]) => [
    name,
    { installed: existsSync(path), path },
  ]),
);

const report = {
  schemaVersion: 1,
  capturedAt: new Date().toISOString(),
  privacy:
    "No serial number, username, microphone name or user content collected.",
  host: {
    architecture: run("uname", ["-m"]).value,
    macosVersion: run("sw_vers", ["-productVersion"]).value,
    buildVersion: run("sw_vers", ["-buildVersion"]).value,
    chip: run("sysctl", ["-n", "machdep.cpu.brand_string"]).value,
    memoryBytes: Number(run("sysctl", ["-n", "hw.memsize"]).value) || null,
    availableStorageBytes: diskFields?.[3]
      ? Number(diskFields[3]) * 1024
      : null,
  },
  targetApplications: applications,
  nextCommand:
    "Run the native matrix in docs/voice-os/RELEASE_GATE_RUNBOOK.md and attach this JSON to the evidence record.",
};

console.log(JSON.stringify(report, null, 2));
