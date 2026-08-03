import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type Database } from "../src/db.js";

const connectionString = process.env.TEST_DATABASE_URL;
const describeWithDatabase = connectionString ? describe : describe.skip;

describeWithDatabase("Neon integration", () => {
  let database: Database;
  const subject = `integration:${randomUUID()}`;
  const deviceIdentifier = `integration-device-${randomUUID()}`;
  let accountID = "";

  beforeAll(async () => {
    database = createDatabase(connectionString!);
    const rows = await database`
      insert into accounts (auth_subject, email)
      values (${subject}, 'integration@press-say.app')
      returning id
    `;
    accountID = String(rows[0]?.id);
  });

  afterAll(async () => {
    if (accountID) {
      await database`delete from accounts where id = ${accountID}::uuid`;
    }
  });

  it("provisions entitlement, device and founding claim constraints", async () => {
    await database`
      insert into entitlements (account_id, plan_code, status, source)
      values (${accountID}::uuid, 'free', 'active', 'grant')
    `;
    const devices = await database`
      insert into devices (account_id, device_identifier, platform, app_version)
      values (${accountID}::uuid, ${deviceIdentifier}, 'macos', '1.2.3')
      returning id
    `;
    const deviceID = String(devices[0]?.id);
    const markerHash = "a".repeat(64);
    const claims = await database`
      insert into founding_claims (
        marker_sha256, account_id, device_id, app_version
      ) values (
        ${markerHash}, ${accountID}::uuid, ${deviceID}::uuid, '1.2.3'
      ) returning marker_sha256
    `;

    expect(claims[0]?.marker_sha256).toBe(markerHash);
  });

  it("deduplicates rate-limit windows atomically", async () => {
    const key = "b".repeat(64);
    const first = await database`
      insert into api_rate_limits (key_sha256, window_start, request_count)
      values (${key}, date_trunc('minute', now()), 1)
      on conflict (key_sha256, window_start) do update
      set request_count = api_rate_limits.request_count + 1
      returning request_count
    `;
    const second = await database`
      insert into api_rate_limits (key_sha256, window_start, request_count)
      values (${key}, date_trunc('minute', now()), 1)
      on conflict (key_sha256, window_start) do update
      set request_count = api_rate_limits.request_count + 1
      returning request_count
    `;

    expect(Number(first[0]?.request_count)).toBe(1);
    expect(Number(second[0]?.request_count)).toBe(2);
  });
});
