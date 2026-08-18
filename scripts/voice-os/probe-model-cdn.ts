import catalog from "../../src-tauri/src/catalog/catalog.json";

const publicRepositories: Record<string, string> = {
  "pressay/parakeet-v3": "memoravox/parakeet-tdt-0.6b-v3-gguf",
  "pressay/whisper-small": "memoravox/whisper-small-gguf",
  "pressay/whisper-large": "memoravox/whisper-large-v3-gguf",
};

async function probe(url: string, expectedBytes: number) {
  const started = performance.now();
  let response = await fetch(url, {
    method: "HEAD",
    redirect: "follow",
    signal: AbortSignal.timeout(20_000),
  });
  if ([403, 405, 501].includes(response.status)) {
    response = await fetch(url, {
      headers: { Range: "bytes=0-0" },
      redirect: "follow",
      signal: AbortSignal.timeout(20_000),
    });
    await response.body?.cancel();
  }
  const contentRange = response.headers.get("content-range");
  const rangeTotal = contentRange?.match(/\/(\d+)$/)?.[1];
  const contentLength = response.headers.get("content-length");
  const advertisedBytes = Number(rangeTotal || contentLength) || null;
  return {
    ok: response.ok && advertisedBytes === expectedBytes,
    status: response.status,
    elapsedMs: Math.round(performance.now() - started),
    advertisedBytes,
    expectedBytes,
    finalHost: new URL(response.url).host,
  };
}

let failed = false;
for (const model of catalog.models) {
  const file = model.files.find(
    (candidate) => candidate.quant === model.default_quant,
  );
  if (!file) throw new Error(`Missing default artifact for ${model.id}`);
  const primary = `${catalog.mirrors[0]}/${model.id}/${model.revision}/${file.filename}`;
  const fallback = `https://huggingface.co/${publicRepositories[model.id]}/resolve/main/${file.filename}?download=true`;
  for (const [route, url] of [
    ["primary", primary],
    ["fallback", fallback],
  ] as const) {
    try {
      const result = await probe(url, file.size_bytes);
      failed ||= !result.ok;
      console.log(JSON.stringify({ model: model.id, route, ...result }));
    } catch (error) {
      failed = true;
      console.log(
        JSON.stringify({
          model: model.id,
          route,
          ok: false,
          error: error instanceof Error ? error.name : "ProbeError",
        }),
      );
    }
  }
}

if (failed) process.exitCode = 1;
