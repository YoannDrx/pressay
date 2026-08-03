import { describe, expect, it } from "vitest";
import {
  deviceLimits,
  isWithinCloudAllowance,
  planFeatures,
  planLimits
} from "../src/entitlements.js";

describe("Pressay entitlements", () => {
  it("keeps BYOK plans out of the managed cloud allowance", () => {
    expect(planLimits.free.cloudTranscriptionSecondsPerMonth).toBe(0);
    expect(planLimits.pro_byok.cloudTranscriptionSecondsPerMonth).toBe(0);
    expect(isWithinCloudAllowance("pro_byok", 0, 60)).toBe(false);
  });

  it("enforces the Cloud monthly transcription limit", () => {
    expect(isWithinCloudAllowance("pro_cloud", 35_900, 100)).toBe(true);
    expect(isWithinCloudAllowance("pro_cloud", 35_900, 101)).toBe(false);
  });

  it("exposes only delivered Free and BYOK feature contracts", () => {
    expect(planFeatures.free).toContain("data.export");
    expect(planFeatures.pro_byok).toContain("modes.custom");
    expect(planFeatures.lifetime_byok).toEqual(planFeatures.pro_byok);
    expect(planFeatures.pro_cloud).toEqual([]);
    expect(deviceLimits.pro_byok).toBe(3);
  });
});
