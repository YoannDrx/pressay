import { describe, expect, it } from "vitest";
import { Hono } from "hono";
import { SignJWT } from "jose";
import { authenticationMiddleware, hasRecentMultiFactorAuthentication, hasRecentStrongAuthentication, type AuthVariables } from "../src/auth.js";
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

  it("accepts a recent signed Better Auth step-up and rejects stale or future proofs", () => {
    expect(hasRecentStrongAuthentication(undefined, 9_500, 10, 10_000)).toBe(true);
    expect(hasRecentStrongAuthentication(undefined, 9_399, 10, 10_000)).toBe(false);
    expect(hasRecentStrongAuthentication(undefined, 10_061, 10, 10_000)).toBe(false);
    expect(hasRecentStrongAuthentication([2, 3], undefined, 10, 10_000)).toBe(true);
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

  it("accepts only short-lived internal proxy tokens from the configured issuer", async () => {
    const internalSecret = "test-internal-jwt-secret-at-least-32-characters";
    const config = readConfig({ ...baseEnvironment, PRESSAY_INTERNAL_JWT_SECRET: internalSecret });
    const app = new Hono<{ Variables: AuthVariables }>();
    app.use("*", authenticationMiddleware(config));
    app.get("/", (context) => context.json({
      subject: context.get("authSubject"),
      provider: context.get("authProvider")
    }));
    const token = await new SignJWT({ email: "verified@example.test", email_verified: true })
      .setProtectedHeader({ alg: "HS256" })
      .setIssuer(config.PRESSAY_INTERNAL_JWT_ISSUER)
      .setAudience("pressay-api")
      .setSubject("user_123")
      .setIssuedAt()
      .setExpirationTime("2m")
      .sign(new TextEncoder().encode(internalSecret));
    const response = await app.request("/", { headers: { Authorization: `Bearer ${token}` } });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ subject: "user_123", provider: "pressay-web" });

    const staleToken = await new SignJWT({ email_verified: true })
      .setProtectedHeader({ alg: "HS256" })
      .setIssuer(config.PRESSAY_INTERNAL_JWT_ISSUER)
      .setAudience("pressay-api")
      .setSubject("user_123")
      .setIssuedAt(Math.floor(Date.now() / 1000) - 301)
      .setExpirationTime("2m")
      .sign(new TextEncoder().encode(internalSecret));
    const staleResponse = await app.request("/", {
      headers: { Authorization: `Bearer ${staleToken}` }
    });
    expect(staleResponse.status).toBe(401);
  });
});
