import { describe, expect, it } from "vitest";
import { createApp } from "../src/application.js";
import { readConfig } from "../src/config.js";
import type { Database } from "../src/db.js";

const config = readConfig({
  DATABASE_URL: "postgresql://example.test/pressay",
  PRESSAY_JWT_ISSUER: "https://identity.example.test",
  PRESSAY_JWT_AUDIENCE: "pressay-api",
  PRESSAY_JWT_JWKS_URL: "https://identity.example.test/jwks.json",
  NODE_ENV: "test"
});

function databaseReturning(rows: unknown[]): Database {
  return (() => Promise.resolve(rows)) as unknown as Database;
}

describe("Pressay API shell", () => {
  it("exposes liveness with a request ID without authentication", async () => {
    const app = createApp(config, databaseReturning([]));
    const response = await app.request("/v1/health", {
      headers: { "X-Request-ID": "test-request-id" }
    });

    expect(response.status).toBe(200);
    expect(response.headers.get("X-Request-ID")).toBe("test-request-id");
    expect(await response.json()).toEqual({
      status: "ok",
      service: "pressay-api"
    });
  });

  it("checks the database on readiness", async () => {
    const app = createApp(config, databaseReturning([{
      table_count: 14,
      column_count: 4
    }]));
    const response = await app.request("/v1/ready");

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      status: "ready",
      database: "reachable",
      schema: "current"
    });
  });

  it("fails readiness when commercial migrations are missing", async () => {
    const app = createApp(config, databaseReturning([{
      table_count: 13,
      column_count: 4
    }]));
    const response = await app.request("/v1/ready");

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({
      status: "unavailable",
      database: "reachable",
      schema: "outdated"
    });
  });

  it("does not collect download metrics without opt-in metrics", async () => {
    const app = createApp(config, databaseReturning([]));
    const response = await app.request("/v1/downloads", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        anonymousID: "9e944211-0ccf-48c2-8bca-f10f66bd428b",
        assetType: "dmg"
      })
    });

    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "feature_disabled" });
  });

  it("does not accept Stripe webhooks until billing is configured", async () => {
    const app = createApp(config, databaseReturning([]));
    const response = await app.request("/v1/webhooks/stripe", {
      method: "POST",
      body: "{}"
    });

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: "billing_not_configured" });
  });

  it("hides the reconciliation endpoint without its cron secret", async () => {
    const app = createApp(config, databaseReturning([]));
    const response = await app.request("/v1/internal/reconcile");

    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "not_found" });
  });
});
