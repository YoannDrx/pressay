const preferredModelsByProvider: Record<string, string[]> = {
  openai: [
    "gpt-5.6-luna",
    "gpt-5.6-terra",
    "gpt-5.6-sol",
    "gpt-5-mini",
    "gpt-4.1-mini",
    "gpt-4o-mini",
  ],
  anthropic: ["claude-sonnet-4-5", "claude-3-5-haiku-latest"],
  groq: ["openai/gpt-oss-20b", "llama-3.3-70b-versatile"],
};

const CURATED_MODEL_LIMIT = 6;

const providerModelNames: Record<string, Record<string, string>> = {
  openai: {
    "gpt-5.6-luna": "GPT-5.6 Luna",
    "gpt-5.6-terra": "GPT-5.6 Terra",
    "gpt-5.6-sol": "GPT-5.6 Sol",
    "gpt-5-mini": "GPT-5 mini",
    "gpt-4.1-mini": "GPT-4.1 mini",
    "gpt-4o-mini": "GPT-4o mini",
  },
};

export const providerModelLabel = (
  providerId: string,
  modelId: string,
): string => providerModelNames[providerId]?.[modelId] ?? modelId;

export const isRecommendedProviderModel = (
  providerId: string,
  modelId: string,
): boolean => providerId === "openai" && modelId === "gpt-5.6-luna";

const openAiNonTextMarkers = [
  "audio",
  "codex",
  "dall-e",
  "embedding",
  "image",
  "moderation",
  "realtime",
  "search",
  "transcribe",
  "tts",
  "whisper",
];

const supportsTextTransformation = (
  providerId: string,
  modelId: string,
): boolean => {
  if (providerId !== "openai") return true;

  const normalized = modelId.toLowerCase();
  const belongsToTextFamily =
    normalized.startsWith("gpt-") || /^o\d(?:-|$)/.test(normalized);
  return (
    belongsToTextFamily &&
    !openAiNonTextMarkers.some((marker) => normalized.includes(marker))
  );
};

export const normalizeProviderModels = (
  providerId: string,
  modelIds: string[],
): string[] => {
  const unique = [
    ...new Set(
      modelIds
        .map((modelId) => modelId.trim())
        .filter(Boolean)
        .filter((modelId) => supportsTextTransformation(providerId, modelId)),
    ),
  ];
  const preferred = preferredModelsByProvider[providerId] ?? [];
  const rank = (modelId: string) => {
    const index = preferred.indexOf(modelId);
    return index === -1 ? Number.MAX_SAFE_INTEGER : index;
  };

  const sorted = unique.sort(
    (left, right) => rank(left) - rank(right) || left.localeCompare(right),
  );

  // Known providers expose very large model inventories that include aliases,
  // dated snapshots and specialist endpoints. Keep the picker intentional while
  // preserving a creatable/manual entry for anything outside the curated set.
  if (preferred.length === 0) return sorted;
  const curated = preferred.filter((modelId) => sorted.includes(modelId));
  return curated.length > 0
    ? curated.slice(0, CURATED_MODEL_LIMIT)
    : sorted.slice(0, CURATED_MODEL_LIMIT);
};

export const chooseInitialProviderModel = (
  providerId: string,
  modelIds: string[],
): string | undefined => normalizeProviderModels(providerId, modelIds)[0];
