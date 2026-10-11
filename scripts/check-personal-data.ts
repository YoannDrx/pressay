import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

/**
 * The repository is public. Operating notes must reference the owner's
 * contact details with placeholders (`<owner email>`), never the values:
 * gitleaks only looks for credentials, not for a personal mailbox, a phone
 * number or a home directory. This scan covers the current tree; history is
 * the owner's decision (see docs/app-store/deployment-plan.fr.md).
 */

export const PERSONAL_DATA_PATTERNS: Record<string, RegExp> = {
  "personal webmail address":
    /[A-Za-z0-9._%+-]+@(?:gmail|googlemail|hotmail|yahoo|outlook|live|icloud|me|free|orange|wanadoo|laposte|sfr)\.[a-z.]{2,6}\b/i,
  "French mobile phone number":
    /(?<![\d.])(?:\+33\s?|0)[67](?:[\s.-]?\d{2}){4}(?!\d)/,
  "personal home directory":
    /\/Users\/(?!someone\b|runner\b|Shared\b)[A-Za-z0-9._-]+\//,
};

const SKIPPED =
  /\.(?:png|jpe?g|gif|icns|ico|webp|onnx|bin|woff2?|ttf|otf|wav|mp3|lock|pdf)$/i;

export function findPersonalData(
  path: string,
  text: string,
): { path: string; line: number; kind: string }[] {
  const findings: { path: string; line: number; kind: string }[] = [];
  text.split("\n").forEach((content, index) => {
    for (const [kind, pattern] of Object.entries(PERSONAL_DATA_PATTERNS)) {
      if (pattern.test(content)) findings.push({ path, line: index + 1, kind });
    }
  });
  return findings;
}

if (import.meta.main) {
  const files = execFileSync("git", ["ls-files", "-z"], { encoding: "utf8" })
    .split("\0")
    .filter((file) => file && !SKIPPED.test(file));
  const findings = files.flatMap((file) => {
    try {
      return findPersonalData(file, readFileSync(file, "utf8"));
    } catch {
      return [];
    }
  });
  // Only locations are printed: the values themselves must not reach CI logs.
  for (const { path, line, kind } of findings) {
    console.error(`${path}:${line}: ${kind}`);
  }
  if (findings.length > 0) {
    console.error(
      "Replace personal data with a placeholder such as <owner email>.",
    );
    process.exit(1);
  }
  console.log(`No personal data pattern in ${files.length} tracked files.`);
}
