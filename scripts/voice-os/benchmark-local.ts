import { existsSync } from "node:fs";
import { loadavg } from "node:os";
import { parseArgs } from "node:util";
import { z } from "zod";
import catalog from "../../src-tauri/src/catalog/catalog.json";

const { values } = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    binary: { type: "string" },
    wav: { type: "string" },
    language: { type: "string" },
    profile: { type: "string" },
    repeat: { type: "string", default: "20" },
    preset: { type: "string" },
    help: { type: "boolean" },
  },
});

if (values.help) {
  console.log(
    "Usage: bun run voice-os:benchmark-local --binary <pressay> --wav <fixture.wav> --language <en|fr|auto> --profile <debug|release> [--repeat 20] [--preset fast|polyglot|precise]\n" +
      "Runs the installed catalogue models sequentially. Writes one JSON record per model without transcript text or local file paths. Use synthetic fixtures; accuracy and microphone-to-paste latency need separate validation.",
  );
  process.exit(0);
}

const options = z
  .object({
    binary: z.string().min(1).refine(existsSync),
    wav: z.string().min(1).refine(existsSync),
    language: z.string().regex(/^[a-z]{2,3}(?:-[A-Za-z]{2,4})?$/),
    profile: z.enum(["debug", "release"]),
    repeat: z.coerce.number().int().min(1).max(100),
    preset: z.enum(["fast", "polyglot", "precise"]).optional(),
  })
  .safeParse(values);
if (!options.success) {
  console.error(
    "Invalid benchmark options. Use --help for the required flags.",
  );
  process.exit(1);
}
if (process.platform !== "darwin") {
  console.error("This benchmark uses the macOS /usr/bin/time memory counters.");
  process.exit(1);
}

// Deliberately exclude transcript text from the native JSON before reporting it.
const outputSchema = z.object({
  model: z.string(),
  language: z.string(),
  bound_backend: z.string(),
  audio_secs: z.number().finite().positive(),
  load_ms: z.number().finite().nonnegative(),
  transcribe_ms: z.array(z.number().finite().nonnegative()).min(1),
});
const presets = {
  fast: "pressay/parakeet-v3",
  polyglot: "pressay/whisper-small",
  precise: "pressay/whisper-large",
} as const;
function median(samples: number[]) {
  const sorted = [...samples].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2
    ? sorted[middle]
    : (sorted[middle - 1] + sorted[middle]) / 2;
}

for (const [preset, id] of Object.entries(presets)) {
  if (options.data.preset && options.data.preset !== preset) continue;
  const model = catalog.models.find((candidate) => candidate.id === id);
  const file = model?.files.find(
    (candidate) => candidate.quant === model.default_quant,
  );
  if (!file)
    throw new Error(`Missing default catalogue artifact for ${preset}`);
  const modelId = `${id}/${file.filename}`;
  const systemLoadAtStart = loadavg();
  const result = Bun.spawnSync(
    [
      "/usr/bin/time",
      "-l",
      options.data.binary,
      "--transcribe-file",
      options.data.wav,
      "--model",
      modelId,
      "--language",
      options.data.language,
      "--repeat",
      String(options.data.repeat),
      "--json",
    ],
    { stdout: "pipe", stderr: "pipe" },
  );
  if (result.exitCode !== 0) {
    // Native stderr can contain local paths or content. Keep it out of evidence.
    console.error(`Benchmark failed for ${preset} (exit ${result.exitCode}).`);
    process.exit(1);
  }
  let output: z.infer<typeof outputSchema>;
  try {
    output = outputSchema.parse(JSON.parse(result.stdout.toString()));
  } catch {
    console.error(`Invalid benchmark JSON for ${preset}. Rebuild the binary.`);
    process.exit(1);
  }
  if (
    output.model !== modelId ||
    output.language !== options.data.language ||
    output.transcribe_ms.length !== options.data.repeat
  ) {
    console.error(`Benchmark configuration mismatch for ${preset}.`);
    process.exit(1);
  }
  const stderr = result.stderr.toString();
  const memory = (pattern: RegExp) => {
    const match = stderr.match(pattern);
    return match ? Number(match[1]) : null;
  };
  const sorted = [...output.transcribe_ms].sort((a, b) => a - b);
  const medianMs = median(sorted);
  console.log(
    JSON.stringify({
      schemaVersion: 1,
      capturedAt: new Date().toISOString(),
      preset,
      profile: options.data.profile,
      ...output,
      medianTranscribeMs: medianMs,
      afterFirstMedianMs:
        sorted.length > 1 ? median(output.transcribe_ms.slice(1)) : null,
      p95TranscribeMs:
        sorted.length >= 20
          ? sorted[Math.ceil(sorted.length * 0.95) - 1]
          : null,
      realTimeFactor: medianMs / (output.audio_secs * 1000),
      maximumResidentBytes: memory(/(\d+)\s+maximum resident set size/),
      peakMemoryFootprintBytes: memory(/(\d+)\s+peak memory footprint/),
      systemLoadAtStart,
      limitation:
        "Model-only process measurement; excludes microphone, insertion, accuracy and total system/GPU memory. Profile is declared by the operator. Other saved engine settings still apply.",
    }),
  );
}
