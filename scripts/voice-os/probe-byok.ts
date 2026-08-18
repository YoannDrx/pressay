type Provider = {
  id: string;
  baseUrl: string;
  keyEnvironment: string;
  keyHeader?: string;
  versionHeader?: [string, string];
};

const providers: Provider[] = [
  {
    id: "openai",
    baseUrl: "https://api.openai.com/v1",
    keyEnvironment: "PRESSAY_BYOK_OPENAI_KEY",
  },
  {
    id: "zai",
    baseUrl: "https://api.z.ai/api/paas/v4",
    keyEnvironment: "PRESSAY_BYOK_ZAI_KEY",
  },
  {
    id: "openrouter",
    baseUrl: "https://openrouter.ai/api/v1",
    keyEnvironment: "PRESSAY_BYOK_OPENROUTER_KEY",
  },
  {
    id: "anthropic",
    baseUrl: "https://api.anthropic.com/v1",
    keyEnvironment: "PRESSAY_BYOK_ANTHROPIC_KEY",
    keyHeader: "x-api-key",
    versionHeader: ["anthropic-version", "2023-06-01"],
  },
  {
    id: "groq",
    baseUrl: "https://api.groq.com/openai/v1",
    keyEnvironment: "PRESSAY_BYOK_GROQ_KEY",
  },
  {
    id: "cerebras",
    baseUrl: "https://api.cerebras.ai/v1",
    keyEnvironment: "PRESSAY_BYOK_CEREBRAS_KEY",
  },
  {
    id: "bedrock_mantle",
    baseUrl: "https://bedrock-mantle.us-east-1.api.aws/v1",
    keyEnvironment: "PRESSAY_BYOK_BEDROCK_MANTLE_KEY",
  },
];

const customUrl = process.env.PRESSAY_BYOK_CUSTOM_URL?.replace(/\/$/, "");
if (customUrl) {
  providers.push({
    id: "custom",
    baseUrl: customUrl,
    keyEnvironment: "PRESSAY_BYOK_CUSTOM_KEY",
  });
}

let configured = 0;
let failed = false;
for (const provider of providers) {
  const key = process.env[provider.keyEnvironment];
  if (!key && provider.id !== "custom") {
    console.log(
      JSON.stringify({
        provider: provider.id,
        status: "skipped",
        reason: `missing:${provider.keyEnvironment}`,
      }),
    );
    continue;
  }
  configured += 1;
  const headers = new Headers({
    Accept: "application/json",
    "User-Agent": "Pressay-contract-probe/1.0",
    Referer: "https://press-say.app",
    "X-Title": "Pressay",
  });
  if (key)
    headers.set(
      provider.keyHeader || "Authorization",
      provider.keyHeader ? key : `Bearer ${key}`,
    );
  if (provider.versionHeader) headers.set(...provider.versionHeader);
  const started = performance.now();
  try {
    const response = await fetch(`${provider.baseUrl}/models`, {
      headers,
      redirect: "error",
      signal: AbortSignal.timeout(15_000),
    });
    const mediaType =
      response.headers.get("content-type")?.split(";")[0] || null;
    const ok = response.ok && mediaType === "application/json";
    failed ||= !ok;
    await response.body?.cancel();
    console.log(
      JSON.stringify({
        provider: provider.id,
        status: ok ? "passed" : "failed",
        httpStatus: response.status,
        mediaType,
        elapsedMs: Math.round(performance.now() - started),
      }),
    );
  } catch (error) {
    failed = true;
    console.log(
      JSON.stringify({
        provider: provider.id,
        status: "failed",
        error: error instanceof Error ? error.name : "ProbeError",
        elapsedMs: Math.round(performance.now() - started),
      }),
    );
  }
}

if (configured === 0) {
  console.error(
    "No provider key configured. Set one PRESSAY_BYOK_*_KEY variable; secret values are never printed.",
  );
  process.exitCode = 2;
} else if (failed) {
  process.exitCode = 1;
}
