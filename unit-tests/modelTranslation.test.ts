import { describe, expect, test } from "bun:test";
import { getModelTranslationId } from "../src/lib/utils/modelTranslation";

describe("model translation ids", () => {
  test("normalizes immutable Pressay catalogue artifact ids", () => {
    expect(
      getModelTranslationId(
        "pressay/parakeet-v3/parakeet-tdt-0.6b-v3-Q8_0.gguf",
      ),
    ).toBe("pressay/parakeet-v3");
    expect(
      getModelTranslationId(
        "pressay/whisper-large/whisper-large-v3-Q5_K_M.gguf",
      ),
    ).toBe("pressay/whisper-large");
  });

  test("keeps stable and third-party ids unchanged", () => {
    expect(getModelTranslationId("pressay/whisper-small")).toBe(
      "pressay/whisper-small",
    );
    expect(getModelTranslationId("parakeet-tdt-0.6b-v3")).toBe(
      "parakeet-tdt-0.6b-v3",
    );
    expect(getModelTranslationId("vendor/model/file.gguf")).toBe(
      "vendor/model/file.gguf",
    );
  });
});
