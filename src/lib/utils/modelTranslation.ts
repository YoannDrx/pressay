import type { TFunction } from "i18next";
import type { ModelInfo } from "@/bindings";

/**
 * The signed Pressay catalogue appends the immutable quantized artifact name
 * to a model id (for example `pressay/whisper-small/whisper-small-Q8_0.gguf`).
 * Translation resources intentionally stay attached to the stable preset id,
 * so that changing an artifact revision never invalidates localized copy.
 */
export function getModelTranslationId(modelId: string): string {
  if (!modelId.startsWith("pressay/")) return modelId;

  const [namespace, preset] = modelId.split("/");
  return preset ? `${namespace}/${preset}` : modelId;
}

/**
 * Get the translated name for a model
 * @param model - The model info object
 * @param t - The translation function from useTranslation
 * @returns The translated model name, or the original name if no translation exists
 */
export function getTranslatedModelName(model: ModelInfo, t: TFunction): string {
  const translationKey = `onboarding.models.${getModelTranslationId(model.id)}.name`;
  const translated = t(translationKey, { defaultValue: "" });
  return translated !== "" ? translated : model.name;
}

/**
 * Get the translated description for a model
 * @param model - The model info object
 * @param t - The translation function from useTranslation
 * @returns The translated model description, or the original description if no translation exists
 */
export function getTranslatedModelDescription(
  model: ModelInfo,
  t: TFunction,
): string {
  // Custom models use a generic translation key
  if (model.is_custom) {
    return t("onboarding.customModelDescription");
  }
  const translationKey = `onboarding.models.${getModelTranslationId(model.id)}.description`;
  const translated = t(translationKey, { defaultValue: "" });
  return translated !== "" ? translated : model.description;
}
