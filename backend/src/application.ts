import {
  createHash,
  createPrivateKey,
  randomUUID,
  sign as signPayload
} from "node:crypto";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { secureHeaders } from "hono/secure-headers";
import type Stripe from "stripe";
import { z } from "zod";
import { authenticationMiddleware, type AuthVariables } from "./auth.js";
import {
  checkoutSessionParameters,
  checkoutInputSchema,
  persistStripeEvent,
  priceID
} from "./billing.js";
import type { AppConfig } from "./config.js";
import type { Database } from "./db.js";
import {
  deviceLimits,
  planFeatures,
  planLimits,
  plans,
  type PlanCode
} from "./entitlements.js";

type Bindings = { Variables: AuthVariables & { requestID: string } };

const usageSchema = z.object({
  transcriptionSeconds: z.number().int().nonnegative().max(14_400).default(0),
  transformations: z.number().int().nonnegative().max(10_000).default(0),
  cloudCharacters: z.number().int().nonnegative().max(10_000_000).default(0),
  idempotencyKey: z.string().uuid()
});

const deviceSchema = z.object({
  deviceIdentifier: z.string().min(8).max(128),
  platform: z.literal("macos"),
  appVersion: z.string().min(1).max(32)
});

const foundingClaimSchema = z.object({
  marker: z.string().min(32).max(256),
  deviceID: z.string().uuid(),
  appVersion: z.literal("1.2.3")
});

export function createApp(
  config: AppConfig,
  database: Database,
  stripe: Stripe | null = null
) {
  const app = new Hono<Bindings>();
  const allowedOrigins = config.PRESSAY_ALLOWED_ORIGINS
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);

  app.use("*", cors({
    origin: allowedOrigins,
    allowHeaders: ["Authorization", "Content-Type", "X-Request-ID"],
    allowMethods: ["GET", "POST", "DELETE", "OPTIONS"],
    maxAge: 86_400
  }));
  app.use("*", secureHeaders({
    crossOriginResourcePolicy: "same-site",
    referrerPolicy: "no-referrer",
    strictTransportSecurity: "max-age=31536000; includeSubDomains"
  }));

  app.use("*", async (context, next) => {
    const startedAt = performance.now();
    const suppliedRequestID = context.req.header("X-Request-ID") ?? "";
    const requestID = /^[A-Za-z0-9._-]{1,128}$/.test(suppliedRequestID)
      ? suppliedRequestID
      : randomUUID();
    context.set("requestID", requestID);
    context.header("X-Request-ID", requestID);
    await next();
    console.info(JSON.stringify({
      event: "http_request",
      requestID,
      method: context.req.method,
      path: context.req.path,
      status: context.res.status,
      durationMs: Math.round(performance.now() - startedAt)
    }));
  });

  app.get("/v1/health", (context) =>
    context.json({ status: "ok", service: "pressay-api" })
  );

  app.get("/v1/ready", async (context) => {
    try {
      await database`select 1 as ready`;
      return context.json({ status: "ready", database: "reachable" });
    } catch {
      return context.json(
        { status: "unavailable", database: "unreachable" },
        503
      );
    }
  });

  app.post("/v1/webhooks/stripe", async (context) => {
    if (!stripe || !config.STRIPE_WEBHOOK_SECRET) {
      return context.json({ error: "billing_not_configured" }, 503);
    }
    const signature = context.req.header("Stripe-Signature");
    if (!signature) {
      return context.json({ error: "missing_stripe_signature" }, 400);
    }
    const rawBody = await context.req.text();
    let event: Stripe.Event;
    try {
      event = await stripe.webhooks.constructEventAsync(
        rawBody,
        signature,
        config.STRIPE_WEBHOOK_SECRET
      );
    } catch {
      return context.json({ error: "invalid_stripe_webhook" }, 400);
    }
    const applied = await persistStripeEvent(database, event, rawBody);
    return context.json({ received: true, applied });
  });

  app.get("/v1/internal/reconcile", async (context) => {
    if (!config.CRON_SECRET ||
        context.req.header("Authorization") !== `Bearer ${config.CRON_SECRET}`) {
      return context.json({ error: "not_found" }, 404);
    }
    const cleanup = await database`
      delete from api_rate_limits
      where window_start < now() - interval '2 days'
      returning key_sha256
    `;
    if (!stripe) {
      return context.json({
        rateLimitWindowsDeleted: cleanup.length,
        subscriptionsReconciled: 0,
        billingConfigured: false
      });
    }
    const subscriptions = await database`
      select stripe_subscription_id
      from billing_customers
      where stripe_subscription_id is not null
    `;
    let reconciled = 0;
    for (const row of subscriptions) {
      if (typeof row.stripe_subscription_id !== "string") continue;
      const subscription = await stripe.subscriptions.retrieve(
        row.stripe_subscription_id
      );
      const now = Math.floor(Date.now() / 1_000);
      const event = {
        id: `reconcile:${subscription.id}:${now}`,
        created: now,
        type: "customer.subscription.updated",
        data: { object: subscription }
      } as unknown as Stripe.Event;
      if (await persistStripeEvent(database, event, JSON.stringify({
        id: subscription.id,
        status: subscription.status
      }))) {
        reconciled += 1;
      }
    }
    return context.json({
      rateLimitWindowsDeleted: cleanup.length,
      subscriptionsReconciled: reconciled,
      billingConfigured: true
    });
  });

  app.use("/v1/*", authenticationMiddleware(config));
  app.use("/v1/*", async (context, next) => {
    const key = createHash("sha256")
      .update(context.get("authSubject"))
      .digest("hex");
    const rows = await database`
      insert into api_rate_limits (key_sha256, window_start, request_count)
      values (${key}, date_trunc('minute', now()), 1)
      on conflict (key_sha256, window_start) do update
      set request_count = api_rate_limits.request_count + 1
      returning request_count
    `;
    const count = Number(rows[0]?.request_count ?? 1);
    context.header("X-RateLimit-Limit", "120");
    context.header("X-RateLimit-Remaining", String(Math.max(0, 120 - count)));
    if (count > 120) {
      context.header("Retry-After", "60");
      return context.json({ error: "rate_limit_exceeded" }, 429);
    }
    await next();
  });

  app.post("/v1/accounts/bootstrap", async (context) => {
    const subject = context.get("authSubject");
    const email = context.get("authEmail") ?? null;
    const name = context.get("authName") ?? null;
    const rows = await database`
      with account as (
        insert into accounts (auth_subject, email, display_name)
        values (${subject}, ${email}, ${name})
        on conflict (auth_subject) do update
        set email = coalesce(excluded.email, accounts.email),
            display_name = coalesce(excluded.display_name, accounts.display_name),
            updated_at = now(),
            deleted_at = null
        returning id, email, display_name, created_at
      ), entitlement as (
        insert into entitlements (account_id, plan_code, status, source)
        select id, 'free', 'active', 'grant' from account
        on conflict (account_id) do nothing
      )
      select * from account
    `;
    return context.json({ account: rows[0] }, 201);
  });

  app.get("/v1/me", async (context) => {
    const subject = context.get("authSubject");
    const rows = await database`
      select id, email, display_name, created_at
      from accounts
      where auth_subject = ${subject} and deleted_at is null
      limit 1
    `;
    if (!rows[0]) return context.json({ error: "account_not_provisioned" }, 404);
    return context.json({ account: rows[0] });
  });

  app.delete("/v1/me", async (context) => {
    const subject = context.get("authSubject");
    const customerRows = await database`
      select b.stripe_customer_id
      from accounts a left join billing_customers b on b.account_id = a.id
      where a.auth_subject = ${subject} and a.deleted_at is null
      limit 1
    `;
    const customerID = customerRows[0]?.stripe_customer_id;
    if (typeof customerID === "string" && !stripe) {
      return context.json({ error: "billing_not_configured" }, 503);
    }
    if (stripe && typeof customerID === "string") {
      try {
        await stripe.customers.del(customerID);
      } catch (error) {
        if (!isStripeResourceMissing(error)) throw error;
      }
    }
    if (config.CLERK_SECRET_KEY) {
      const clerkResponse = await fetch(
        `https://api.clerk.com/v1/users/${encodeURIComponent(subject)}`,
        {
          method: "DELETE",
          headers: { Authorization: `Bearer ${config.CLERK_SECRET_KEY}` }
        }
      );
      if (!clerkResponse.ok && clerkResponse.status !== 404) {
        return context.json({ error: "identity_deletion_failed" }, 502);
      }
    } else if (config.NODE_ENV === "production") {
      return context.json({ error: "identity_deletion_not_configured" }, 503);
    }
    const rows = await database`
      delete from accounts
      where auth_subject = ${subject}
      returning id
    `;
    if (!rows[0]) return context.json({ error: "account_not_provisioned" }, 404);
    return context.body(null, 204);
  });

  app.get("/v1/entitlements", async (context) => {
    const subject = context.get("authSubject");
    const rows = await database`
      select coalesce(e.plan_code, 'free') as plan_code,
             coalesce(e.status, 'active') as status,
             coalesce(e.source, 'grant') as source,
             e.trial_end,
             e.current_period_end,
             e.founding_claimed_at
      from accounts a
      left join entitlements e on e.account_id = a.id
      where a.auth_subject = ${subject} and a.deleted_at is null
      limit 1
    `;
    const row = rows[0];
    if (!row) return context.json({ error: "account_not_provisioned" }, 404);
    const plan = plans.includes(row.plan_code as PlanCode)
      ? (row.plan_code as PlanCode)
      : "free";
    const active = ["active", "trialing"].includes(String(row.status));
    const isFoundingUser = row.founding_claimed_at != null || row.source === "legacy";
    const effectivePlan: PlanCode = active || isFoundingUser ? plan : "free";
    const issuedAt = new Date();
    const graceLimit = new Date(issuedAt.getTime() + 14 * 86_400_000);
    const contractualEnd = earliestDate(row.trial_end, row.current_period_end);
    const offlineValidUntil = contractualEnd && contractualEnd < graceLimit
      ? contractualEnd
      : graceLimit;
    const entitlement = {
      plan,
      status: row.status,
      source: row.source,
      features: planFeatures[effectivePlan],
      trialEnd: row.trial_end,
      currentPeriodEnd: row.current_period_end,
      offlineValidUntil: offlineValidUntil.toISOString(),
      isFoundingUser,
      deviceLimit: deviceLimits[effectivePlan],
      limits: planLimits[effectivePlan],
      issuedAt: issuedAt.toISOString()
    };
    return context.json({
      ...entitlement,
      snapshot: signEntitlement(entitlement, config.PRESSAY_ENTITLEMENT_SIGNING_PRIVATE_KEY)
    });
  });

  app.post("/v1/devices/register", async (context) => {
    const input = deviceSchema.parse(await context.req.json());
    const subject = context.get("authSubject");
    const rows = await database`
      with account as (
        select a.id,
               case
                 when e.status in ('active', 'trialing') then coalesce(e.plan_code, 'free')
                 when e.source = 'legacy' then coalesce(e.plan_code, 'free')
                 else 'free'
               end as plan_code,
               pg_advisory_xact_lock(hashtextextended(a.id::text, 0))
        from accounts a
        left join entitlements e on e.account_id = a.id
        where a.auth_subject = ${subject} and a.deleted_at is null
      ), active_devices as (
        select count(*)::integer as count
        from devices d join account a on a.id = d.account_id
        where d.revoked_at is null
          and d.device_identifier <> ${input.deviceIdentifier}
      )
      insert into devices (
        account_id, device_identifier, platform, app_version, revoked_at
      )
      select id, ${input.deviceIdentifier}, ${input.platform}, ${input.appVersion}, null
      from account, active_devices
      where active_devices.count < case account.plan_code
        when 'free' then 1 else 3 end
      on conflict (account_id, device_identifier)
      do update set app_version = excluded.app_version,
                    last_seen_at = now(), revoked_at = null
      returning id, device_identifier, last_seen_at
    `;
    if (!rows[0]) return context.json({ error: "device_limit_reached" }, 409);
    return context.json({ device: rows[0] }, 201);
  });

  app.get("/v1/devices", async (context) => {
    const subject = context.get("authSubject");
    const rows = await database`
      select d.id, d.device_identifier, d.platform, d.app_version,
             d.created_at, d.last_seen_at
      from devices d join accounts a on a.id = d.account_id
      where a.auth_subject = ${subject}
        and a.deleted_at is null
        and d.revoked_at is null
      order by d.last_seen_at desc
    `;
    return context.json({ devices: rows });
  });

  app.delete("/v1/devices/:id", async (context) => {
    const deviceID = z.string().uuid().parse(context.req.param("id"));
    const subject = context.get("authSubject");
    const rows = await database`
      update devices d set revoked_at = now()
      from accounts a
      where d.id = ${deviceID}::uuid
        and d.account_id = a.id
        and a.auth_subject = ${subject}
        and a.deleted_at is null
        and d.revoked_at is null
      returning d.id
    `;
    if (!rows[0]) return context.json({ error: "device_not_found" }, 404);
    return context.body(null, 204);
  });

  app.post("/v1/founding/claim", async (context) => {
    const input = foundingClaimSchema.parse(await context.req.json());
    const deadline = config.PRESSAY_FOUNDING_CLAIM_DEADLINE;
    if (deadline && Date.now() > deadline.getTime()) {
      return context.json({ error: "founding_claim_closed" }, 410);
    }
    const markerHash = createHash("sha256").update(input.marker).digest("hex");
    const subject = context.get("authSubject");
    const rows = await database`
      with eligible_device as (
        select a.id as account_id, d.id as device_id
        from accounts a join devices d on d.account_id = a.id
        where a.auth_subject = ${subject}
          and a.deleted_at is null
          and d.id = ${input.deviceID}::uuid
          and d.revoked_at is null
          and d.app_version = ${input.appVersion}
      ), claimed as (
        insert into founding_claims (
          marker_sha256, account_id, device_id, app_version
        )
        select ${markerHash}, account_id, device_id, ${input.appVersion}
        from eligible_device
        on conflict do nothing
        returning account_id
      ), eligible_claim as (
        select account_id from claimed
        union
        select f.account_id
        from founding_claims f
        join eligible_device d on d.account_id = f.account_id
        where f.marker_sha256 = ${markerHash}
      )
      insert into entitlements (
        account_id, plan_code, status, source, founding_claimed_at
      )
      select account_id, 'lifetime_byok', 'active', 'legacy', now()
      from eligible_claim
      on conflict (account_id) do update
      set plan_code = 'lifetime_byok', status = 'active', source = 'legacy',
          founding_claimed_at = coalesce(entitlements.founding_claimed_at, now()),
          updated_at = now()
      returning account_id
    `;
    if (!rows[0]) {
      return context.json({ error: "founding_claim_invalid_or_already_used" }, 409);
    }
    return context.json({ claimed: true, plan: "lifetime_byok" });
  });

  app.post("/v1/usage", async (context) => {
    const input = usageSchema.parse(await context.req.json());
    const subject = context.get("authSubject");
    const rows = await database`
      with account as (
        select id from accounts where auth_subject = ${subject} and deleted_at is null
      ), inserted_event as (
        insert into usage_events (
          account_id, idempotency_key, transcription_seconds,
          transformations, cloud_characters
        )
        select id, ${input.idempotencyKey}::uuid, ${input.transcriptionSeconds},
               ${input.transformations}, ${input.cloudCharacters}
        from account
        on conflict (account_id, idempotency_key) do nothing
        returning account_id, transcription_seconds, transformations, cloud_characters
      )
      insert into usage_monthly (
        account_id, period_start, transcription_seconds,
        transformations, cloud_characters
      )
      select account_id, date_trunc('month', now())::date,
             transcription_seconds, transformations, cloud_characters
      from inserted_event
      on conflict (account_id, period_start) do update
      set transcription_seconds = usage_monthly.transcription_seconds + excluded.transcription_seconds,
          transformations = usage_monthly.transformations + excluded.transformations,
          cloud_characters = usage_monthly.cloud_characters + excluded.cloud_characters,
          updated_at = now()
      returning transcription_seconds, transformations, cloud_characters, period_start
    `;
    return context.json({ usage: rows[0] ?? null, duplicate: !rows[0] });
  });

  app.post("/v1/billing/checkout", async (context) => {
    if (!stripe || !config.PRESSAY_CHECKOUT_SUCCESS_URL ||
        !config.PRESSAY_CHECKOUT_CANCEL_URL) {
      return context.json({ error: "billing_not_configured" }, 503);
    }
    const input = checkoutInputSchema.parse(await context.req.json());
    const selectedPriceID = priceID(config, input.plan, input.interval);
    if (!selectedPriceID) {
      return context.json({ error: "price_not_configured" }, 503);
    }
    const subject = context.get("authSubject");
    const rows = await database`
      select a.id, a.email, b.stripe_customer_id,
             (not exists (
                 select 1 from account_trials t where t.account_id = a.id
               ) and (
                 ${input.deviceID ?? null}::uuid is null
                 or exists (
                 select 1 from devices d
                 where d.id = ${input.deviceID ?? null}::uuid
                   and d.account_id = a.id and d.revoked_at is null
               )
               )) as trial_eligible
      from accounts a
      left join billing_customers b on b.account_id = a.id
      where a.auth_subject = ${subject} and a.deleted_at is null
      limit 1
    `;
    const account = rows[0];
    if (!account) return context.json({ error: "account_not_provisioned" }, 404);

    let customerID = account.stripe_customer_id as string | null;
    if (!customerID) {
      const customer = await stripe.customers.create({
        ...(typeof account.email === "string" ? { email: account.email } : {}),
        metadata: { account_id: String(account.id) }
      });
      customerID = customer.id;
      await database`
        insert into billing_customers (account_id, stripe_customer_id)
        values (${String(account.id)}::uuid, ${customerID})
        on conflict (account_id) do update
        set stripe_customer_id = excluded.stripe_customer_id, updated_at = now()
      `;
    }

    const trialEligible = input.interval !== "lifetime"
      && account.trial_eligible === true;
    const metadata = {
      account_id: String(account.id),
      plan_code: input.plan,
      ...(trialEligible && input.deviceID ? { device_id: input.deviceID } : {})
    };
    const session = await stripe.checkout.sessions.create(
      checkoutSessionParameters({
        customerID,
        priceID: selectedPriceID,
        metadata,
        interval: input.interval,
        trialEligible,
        successURL: config.PRESSAY_CHECKOUT_SUCCESS_URL,
        cancelURL: config.PRESSAY_CHECKOUT_CANCEL_URL
      })
    );
    await database`
      update billing_customers set last_checkout_at = now(), updated_at = now()
      where account_id = ${String(account.id)}::uuid
    `;
    return context.json({ url: session.url });
  });

  app.post("/v1/billing/portal", async (context) => {
    if (!stripe || !config.PRESSAY_BILLING_RETURN_URL) {
      return context.json({ error: "billing_not_configured" }, 503);
    }
    const subject = context.get("authSubject");
    const rows = await database`
      select b.stripe_customer_id
      from accounts a join billing_customers b on b.account_id = a.id
      where a.auth_subject = ${subject} and a.deleted_at is null
      limit 1
    `;
    const customerID = rows[0]?.stripe_customer_id;
    if (typeof customerID !== "string") {
      return context.json({ error: "billing_customer_not_found" }, 404);
    }
    const session = await stripe.billingPortal.sessions.create({
      customer: customerID,
      return_url: config.PRESSAY_BILLING_RETURN_URL
    });
    return context.json({ url: session.url });
  });

  app.onError((error, context) => {
    if (error instanceof z.ZodError) {
      return context.json({ error: "invalid_request", issues: error.issues }, 400);
    }
    console.error(JSON.stringify({
      event: "request_error",
      requestID: context.get("requestID"),
      errorType: error instanceof Error ? error.name : "unknown"
    }));
    return context.json({
      error: "internal_error",
      requestID: context.get("requestID")
    }, 500);
  });

  return app;
}

function signEntitlement(
  entitlement: object,
  encodedPrivateKey: string | undefined
): { algorithm: "Ed25519"; payload: string; value: string } | null {
  if (!encodedPrivateKey) return null;
  const privateKey = createPrivateKey({
    key: Buffer.from(encodedPrivateKey, "base64"),
    format: "der",
    type: "pkcs8"
  });
  const payload = Buffer.from(JSON.stringify(entitlement));
  return {
    algorithm: "Ed25519",
    payload: payload.toString("base64"),
    value: signPayload(null, payload, privateKey).toString("base64")
  };
}

function earliestDate(...values: unknown[]): Date | null {
  const dates = values
    .filter(
      (value): value is string | Date =>
        typeof value === "string" || value instanceof Date
    )
    .map((value) => new Date(value))
    .filter((value) => !Number.isNaN(value.getTime()))
    .sort((left, right) => left.getTime() - right.getTime());
  return dates[0] ?? null;
}

function isStripeResourceMissing(error: unknown): boolean {
  return typeof error === "object"
    && error !== null
    && "code" in error
    && error.code === "resource_missing";
}
