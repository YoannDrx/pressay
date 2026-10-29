/**
 * Bun on the windows-11-arm runner skips the native optional packages built
 * for win32/arm64 (Tauri CLI, rollup, esbuild, lightningcss, tailwind oxide).
 * Install each one the lockfile pins, from the npm registry, and refuse any
 * tarball whose integrity differs from bun.lock.
 */
import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  renameSync,
} from "node:fs";
import { join } from "node:path";

const lock = readFileSync("bun.lock", "utf8");
const entry =
  /"([^"]+)": \["((?:@[^@"/]+\/)?[^@"]+)@([^"]+)", "", \{ "os": "win32", "cpu": "arm64" \}, "(sha512-[^"]+)"\]/g;

// npm is npm.cmd on Windows; resolve it through PATHEXT.
const npm = Bun.which("npm");
if (!npm) throw new Error("npm is not available");

let installed = 0;
for (const [, key, name, version, integrity] of lock.matchAll(entry)) {
  if (key !== name) {
    throw new Error(`Nested native package ${key} is not handled`);
  }
  const target = join("node_modules", ...name.split("/"));
  if (existsSync(target)) continue;

  // Inside the checkout so the final rename never crosses drives.
  mkdirSync(".arm64-packages", { recursive: true });
  const workdir = mkdtempSync(join(".arm64-packages", "package-"));
  const pack = Bun.spawnSync(
    [npm, "pack", `${name}@${version}`, "--pack-destination", workdir],
    { stderr: "inherit" },
  );
  if (pack.exitCode !== 0) throw new Error(`npm pack failed for ${name}`);
  const tarball = join(
    workdir,
    pack.stdout.toString().trim().split(/\r?\n/).at(-1)!,
  );
  const digest = `sha512-${createHash("sha512").update(readFileSync(tarball)).digest("base64")}`;
  if (digest !== integrity) {
    throw new Error(`${name}@${version} does not match the bun.lock integrity`);
  }
  const extract = Bun.spawnSync(["tar", "-xzf", tarball, "-C", workdir], {
    stderr: "inherit",
  });
  if (extract.exitCode !== 0) throw new Error(`Unable to extract ${name}`);
  mkdirSync(join(target, ".."), { recursive: true });
  renameSync(join(workdir, "package"), target);
  console.log(`Installed ${name}@${version}`);
  installed += 1;
}
console.log(`Windows ARM64 native packages installed: ${installed}`);
