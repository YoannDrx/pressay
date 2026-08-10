import { describe, expect, it } from "vitest";
import { hasRecentMultiFactorAuthentication } from "../src/auth.js";
import { readConfig } from "../src/config.js";

const baseEnvironment = {
  DATABASE_URL: "postgresql://example.test/pressay",
  PRESSAY_JWT_ISSUER: "https://identity.example.test",
  PRESSAY_JWT_AUDIENCE: "pressay-api",
  PRESSAY_JWT_JWKS_URL: "https://identity.example.test/jwks.json",
  NODE_ENV: "test"
};

describe("administrative authentication", () => {
  it("requires both factors to be recent", () => {
    expect(hasRecentMultiFactorAuthentication([2, 3], 10)).toBe(true);
    expect(hasRecentMultiFactorAuthentication([2, -1], 10)).toBe(false);
    expect(hasRecentMultiFactorAuthentication([2, 11], 10)).toBe(false);
    expect(hasRecentMultiFactorAuthentication(undefined, 10)).toBe(false);
  });

  it("keeps every commercial capability disabled by default", () => {
    const config = readConfig(baseEnvironment);
    expect(config.PRESSAY_OWNER_EMAIL).toBe("yoann.andrieux@gmail.com");
    expect(config.ADMIN_ENABLED).toBe(false);
    expect(config.COMMERCIAL_CHECKOUT_ENABLED).toBe(false);
    expect(config.FOUNDING_CLAIMS_ENABLED).toBe(false);
    expect(config.ACCESS_CAMPAIGNS_ENABLED).toBe(false);
    expect(config.REFERRALS_ENABLED).toBe(false);
    expect(config.REMOTE_METRICS_ENABLED).toBe(false);
  });

  it("parses explicit feature flags without truthy string mistakes", () => {
    const config = readConfig({
      ...baseEnvironment,
      ADMIN_ENABLED: "true",
      REFERRALS_ENABLED: "0"
    });
    expect(config.ADMIN_ENABLED).toBe(true);
    expect(config.REFERRALS_ENABLED).toBe(false);
  });
});
