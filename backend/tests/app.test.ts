import { describe, expect, it } from "vitest";
import { createApp } from "../src/app.js";
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
    const app = createApp(config, databaseReturning([{ ready: 1 }]));
    const response = await app.request("/v1/ready");

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      status: "ready",
      database: "reachable"
    });
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
