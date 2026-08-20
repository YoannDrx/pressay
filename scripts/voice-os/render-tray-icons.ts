import { copyFile, readdir } from "node:fs/promises";
import { basename, resolve } from "node:path";

const sourceDirectory = resolve(
  import.meta.dirname,
  "../../design-assets/tray",
);
const outputDirectory = resolve(
  import.meta.dirname,
  "../../src-tauri/resources",
);

const sources = (await readdir(sourceDirectory))
  .filter((file) => file.startsWith("signal-") && file.endsWith(".svg"))
  .sort();

for (const source of sources) {
  const name = basename(source, ".svg");
  const output = resolve(outputDirectory, `tray_${name}.png`);
  const result = Bun.spawnSync(
    [
      "rsvg-convert",
      "--width",
      "64",
      "--height",
      "64",
      "--output",
      output,
      resolve(sourceDirectory, source),
    ],
    { stderr: "pipe" },
  );
  if (result.exitCode !== 0) {
    throw new Error(
      `Failed to render ${source}: ${result.stderr.toString().trim()}`,
    );
  }
  await copyFile(output, resolve(outputDirectory, `tray_${name}_light.png`));
}

console.log(`Rendered ${sources.length} Signal Circle tray sources.`);
