import { describe, expect, test } from "bun:test";
import {
  chooseInitialProviderModel,
  normalizeProviderModels,
} from "../src/lib/providerModels";

describe("provider model selection", () => {
  test("prefers a current low-latency OpenAI text model", () => {
    expect(
      chooseInitialProviderModel("openai", [
        "gpt-4o-mini",
        "gpt-5.2",
        "gpt-5-mini",
      ]),
    ).toBe("gpt-5-mini");
  });

  test("prefers GPT-5.6 Luna when the account exposes it", () => {
    expect(
      chooseInitialProviderModel("openai", [
        "gpt-5.6-sol",
        "gpt-5.6-luna",
        "gpt-5.6-terra",
      ]),
    ).toBe("gpt-5.6-luna");
  });

  test("keeps the known-provider picker intentionally short", () => {
    expect(
      normalizeProviderModels("openai", [
        "gpt-5.6-luna",
        "gpt-5.6-terra",
        "gpt-5.6-sol",
        "gpt-5-mini",
        "gpt-4.1-mini",
        "gpt-4o-mini",
        "gpt-4.1",
      ]),
    ).toHaveLength(6);
  });

  test("removes OpenAI models that cannot transform text", () => {
    expect(
      normalizeProviderModels("openai", [
        "text-embedding-3-small",
        "gpt-5-mini",
        "gpt-realtime-mini",
        "gpt-4o-mini-transcribe",
        "gpt-5-mini",
      ]),
    ).toEqual(["gpt-5-mini"]);
  });

  test("keeps custom provider model identifiers", () => {
    expect(
      normalizeProviderModels("custom", ["local/chat", "local/chat"]),
    ).toEqual(["local/chat"]);
  });
});
