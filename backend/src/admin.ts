import { createHash, randomBytes, randomUUID } from "node:crypto";
import type { Hono, MiddlewareHandler } from "hono";
import type Stripe from "stripe";
import { z } from "zod";
import { hasRecentStrongAuthentication, type AuthVariables } from "./auth.js";
import type { AppConfig } from "./config.js";
import type { Database } from "./db.js";
import { reconcileStripeSubscriptions } from "./billing.js";
import { processReferralStripeEvent } from "./commercial.js";

export const adminRoles = ["owner", "support", "billing", "viewer"] as const;
export type AdminRole = (typeof adminRoles)[number];

export type AdminVariables = AuthVariables & {
  requestID: string;
  adminAccountID: string;
  adminRole: AdminRole;
};

const reasonSchema = z.string().trim().min(3).max(1_000);
const uuidSchema = z.string().uuid();

const grantSchema = z.object({
  plan: z.enum(["pro_byok", "lifetime_byok"]),
  durationDays: z.number().int().min(1).max(365).optional(),
  reason: reasonSchema
}).superRefine((input, context) => {
  if (input.plan === "pro_byok" && input.durationDays == null) {
    context.addIssue({ code: "custom", message: "durationDays is required for Pro grants" });
  }
  if (input.plan === "lifetime_byok" && input.durationDays != null) {
    context.addIssue({ code: "custom", message: "Lifetime grants cannot have a duration" });
  }
});

const campaignSchema = z.object({
  kind: z.enum(["access_grant", "stripe_discount"]),
  delivery: z.enum(["code", "link"]),
  plan: z.enum(["pro_byok", "lifetime_byok"]).optional(),
  durationDays: z.number().int().min(1).max(365).optional(),
  discountPercent: z.number().int().min(1).max(100).optional(),
  discountAmount: z.number().int().positive().optional(),
  maxRedemptions: z.number().int().positive().max(100_000).default(1),
  startsAt: z.string().datetime().optional(),
  expiresAt: z.string().datetime().optional(),
  restrictedEmail: z.string().email().optional(),
  restrictedDomain: z.string().min(3).max(253).optional(),
  internalNote: z.string().trim().max(2_000).optional(),
  reason: reasonSchema
}).superRefine((input, context) => {
  if (input.kind === "access_grant") {
    if (!input.plan) context.addIssue({ code: "custom", message: "plan is required" });
    if (input.plan === "pro_byok" && input.durationDays == null) {
      context.addIssue({ code: "custom", message: "durationDays is required" });
    }
    if (input.discountPercent != null || input.discountAmount != null) {
      context.addIssue({ code: "custom", message: "access grants cannot include a Stripe discount" });
    }
  } else if ((input.discountPercent == null) === (input.discountAmount == null)) {
    context.addIssue({ code: "custom", message: "provide exactly one Stripe discount" });
  } else if (input.delivery !== "code") {
    context.addIssue({ code: "custom", message: "Stripe discounts must use a customer-facing code" });
  }
});

const refundSchema = z.object({
  paymentIntentID: z.string().startsWith("pi_"),
  amount: z.number().int().positive().optional(),
  reason: reasonSchema,
  idempotencyKey: z.string().uuid()
});

export function registerAdminRoutes(
  app: Hono<{ Variables: AdminVariables }>,
  config: AppConfig,
  database: Database,
  stripe: Stripe | null
): void {
  app.use("/v1/admin/*", adminAuthentication(config, database));
  app.use("/v1/admin/*", async (context, next) => {
    if (!["GET", "HEAD", "OPTIONS"].includes(context.req.method) && !config.ADMIN_MUTATIONS_ENABLED) {
      return context.json({ error: "admin_read_only" }, 403);
    }
    await next();
  });

  app.get("/v1/admin/overview", requireRoles("owner", "support", "billing", "viewer"), async (context) => {
    const [accounts, plans, downloads, referrals, billing] = await Promise.all([
      database`
        select count(*) filter (where deleted_at is null)::integer as total,
               count(*) filter (where deleted_at is null and created_at >= now() - interval '30 days')::integer as new_30d
        from accounts
      `,
      database`
        select coalesce(e.plan_code, 'free') as plan, count(*)::integer as count,
               coalesce(sum(case
                 when b.subscription_interval = 'monthly' then b.subscription_unit_amount
                 when b.subscription_interval = 'annual' then b.subscription_unit_amount / 12.0
                 else 0 end) filter (where e.status in ('active', 'trialing')), 0) as mrr_minor
        from accounts a left join entitlements e on e.account_id = a.id
        left join billing_customers b on b.account_id = a.id
        where a.deleted_at is null group by coalesce(e.plan_code, 'free')
      `,
      database`
        select count(*) filter (where occurred_at >= now() - interval '30 days')::integer as last_30d,
               count(*)::integer as total from download_events
      `,
      database`
        select count(*)::integer as attributed,
               count(*) filter (where status in ('qualified', 'rewarded'))::integer as converted
        from referral_attributions
      `,
      database`
        select count(*) filter (where status = 'failed')::integer as failed_webhooks,
               max(processed_at) as last_webhook_at
        from billing_events where provider = 'stripe'
      `
    ]);
    return context.json({
      users: accounts[0] ?? { total: 0, new_30d: 0 },
      plans,
      downloads: downloads[0] ?? { total: 0, last_30d: 0 },
      referrals: referrals[0] ?? { attributed: 0, converted: 0 },
      billing: billing[0] ?? { failed_webhooks: 0, last_webhook_at: null },
      privacy: { contentCollected: false, unknownMeansNoAccountOrConsent: true }
    });
  });

  app.get("/v1/admin/releases", requireRoles("owner", "support", "viewer"), async (context) => {
    const rows = await database`
      select app_version, architecture, distribution_channel,
             count(*) filter (where revoked_at is null)::integer as active_devices,
             count(distinct account_id) filter (where revoked_at is null)::integer as active_accounts,
             max(last_seen_at) as last_seen_at
      from devices
      group by app_version, architecture, distribution_channel
      order by max(last_seen_at) desc
    `;
    return context.json({ releases: rows });
  });

  app.get("/v1/admin/health", requireRoles("owner", "support", "billing", "viewer"), async (context) => {
    const startedAt = performance.now();
    const [databaseStatus, billing, jobs, rewards] = await Promise.all([
      database`select now() as database_time`,
      database`
        select count(*) filter (where status = 'failed')::integer as failed,
               count(*) filter (where status = 'processing' and processed_at < now() - interval '10 minutes')::integer as stuck,
               max(processed_at) as latest
        from billing_events where provider = 'stripe'
      `,
      database`select count(*) filter (where status = 'failed')::integer as failed, count(*) filter (where status = 'pending' and execute_after < now())::integer as overdue from deletion_jobs`,
      database`select count(*) filter (where status = 'failed')::integer as failed from referral_rewards`
    ]);
    return context.json({
      api: { status: "ok", latencyMs: Math.round(performance.now() - startedAt), requestID: context.get("requestID") },
      database: { status: databaseStatus[0] ? "reachable" : "unreachable", time: databaseStatus[0]?.database_time },
      billing: billing[0] ?? { failed: 0, stuck: 0, latest: null },
      deletionJobs: jobs[0] ?? { failed: 0, overdue: 0 },
      referralRewards: rewards[0] ?? { failed: 0 },
      flags: {
        admin: config.ADMIN_ENABLED,
        adminMutations: config.ADMIN_MUTATIONS_ENABLED,
        checkout: config.COMMERCIAL_CHECKOUT_ENABLED,
        campaigns: config.ACCESS_CAMPAIGNS_ENABLED,
        referrals: config.REFERRALS_ENABLED,
        remoteMetrics: config.REMOTE_METRICS_ENABLED
      }
    });
  });

  app.get("/v1/admin/users", requireRoles("owner", "support", "billing", "viewer"), async (context) => {
    const search = (context.req.query("search") ?? "").trim().slice(0, 200);
    const plan = context.req.query("plan") ?? "";
    const status = context.req.query("status") ?? "";
    const cursor = context.req.query("cursor") ?? "";
    const limit = Math.min(100, Math.max(1, Number.parseInt(context.req.query("limit") ?? "50", 10) || 50));
    const rows = await database`
      select id, email, display_name, created_at, updated_at, deleted_at,
             subscription_plan, subscription_status, subscription_source,
             subscription_end, active_device_count, last_device_seen_at,
             transcription_seconds, transformations, cloud_characters,
             active_grant_end, has_lifetime_grant
      from admin_user_summary
      where (${search} = '' or coalesce(email, '') ilike ${`%${search}%`} or coalesce(display_name, '') ilike ${`%${search}%`} or id::text = ${search})
        and (${plan} = '' or subscription_plan = ${plan})
        and (${status} = '' or subscription_status = ${status})
        and (${cursor} = '' or created_at < (select created_at from accounts where id = nullif(${cursor}, '')::uuid))
      order by created_at desc, id desc
      limit ${limit + 1}
    `;
    const page = rows.slice(0, limit);
    if (context.req.query("format") === "csv") {
      const header = "id,email,name,plan,status,created_at,active_devices\n";
      const csv = header + page.map((row) => [
        row.id, row.email, row.display_name, row.subscription_plan,
        row.subscription_status, row.created_at, row.active_device_count
      ].map(csvCell).join(",")).join("\n");
      context.header("Content-Type", "text/csv; charset=utf-8");
      context.header("Content-Disposition", `attachment; filename="pressay-users-${new Date().toISOString().slice(0, 10)}.csv"`);
      return context.body(csv);
    }
    return context.json({ users: page, nextCursor: rows.length > limit ? String(page.at(-1)?.id) : null });
  });

  app.get("/v1/admin/users/:id", requireRoles("owner", "support", "billing", "viewer"), async (context) => {
    const accountID = uuidSchema.parse(context.req.param("id"));
    const [account, devices, grants, billing, transactions, referrals, notes, audit] = await Promise.all([
      database`select * from admin_user_summary where id = ${accountID}::uuid limit 1`,
      database`
        select id, platform, app_version, distribution_channel, architecture, os_major,
               transcription_engine, telemetry_consent, created_at, last_seen_at, revoked_at
        from devices where account_id = ${accountID}::uuid order by last_seen_at desc
      `,
      database`
        select id, plan_code, source, starts_at, ends_at, revoked_at, reason, created_at
        from entitlement_grants where account_id = ${accountID}::uuid order by created_at desc
      `,
      database`
        select stripe_customer_id, stripe_subscription_id, subscription_interval,
               subscription_unit_amount, currency, last_checkout_at, updated_at
        from billing_customers where account_id = ${accountID}::uuid
      `,
      database`
        select provider_object_id, provider_event_id, transaction_type, amount,
               currency, status, occurred_at
        from billing_transactions where account_id = ${accountID}::uuid
        order by occurred_at desc limit 100
      `,
      database`
        select ra.*, rc.code
        from referral_attributions ra
        join referral_codes rc on rc.account_id = ra.referrer_account_id
        where ra.referrer_account_id = ${accountID}::uuid or ra.referee_account_id = ${accountID}::uuid
        order by ra.attributed_at desc
      `,
      database`
        select id, category, body, created_at, created_by
        from support_notes where account_id = ${accountID}::uuid and deleted_at is null order by created_at desc
      `,
      database`
        select id, actor_role, action, permission, reason, result, created_at, request_id
        from admin_audit_log where target_id = ${accountID} order by created_at desc limit 100
      `
    ]);
    if (!account[0]) return context.json({ error: "user_not_found" }, 404);
    return context.json({
      account: account[0], devices, grants, billing: billing[0] ?? null, transactions,
      referrals, notes, audit,
      unavailableData: ["audio", "transcription", "local_history", "selected_text", "files", "byok_key", "clipboard", "screenshots"]
    });
  });

  app.post("/v1/admin/users/:id/grants", requireRoles("owner", "support"), async (context) => {
    const accountID = uuidSchema.parse(context.req.param("id"));
    const input = grantSchema.parse(await context.req.json());
    if (input.plan === "lifetime_byok") {
      if (context.get("adminRole") !== "owner") return context.json({ error: "insufficient_role" }, 403);
      if (!hasRecentMFA(context, config)) return context.json({ error: "recent_mfa_required" }, 403);
    }
    const rows = await database`
      insert into entitlement_grants (
        account_id, plan_code, source, starts_at, ends_at, created_by, reason
      ) values (
        ${accountID}::uuid, ${input.plan}, 'manual', now(),
        case when ${input.durationDays ?? null}::integer is null then null else now() + (${input.durationDays ?? null}::integer * interval '1 day') end,
        ${context.get("adminAccountID")}::uuid, ${input.reason}
      ) returning id, account_id, plan_code, starts_at, ends_at
    `;
    if (!rows[0]) return context.json({ error: "user_not_found" }, 404);
    await audit(database, context, "entitlements.grant", "create_grant", "account", accountID, input.reason, null, rows[0]);
    return context.json({ grant: rows[0] }, 201);
  });

  app.delete("/v1/admin/grants/:id", requireRoles("owner", "support"), async (context) => {
    const grantID = uuidSchema.parse(context.req.param("id"));
    const body = z.object({ reason: reasonSchema }).parse(await context.req.json());
    const before = await database`select id, account_id, plan_code, source, ends_at, revoked_at from entitlement_grants where id = ${grantID}::uuid`;
    if (!before[0]) return context.json({ error: "grant_not_found" }, 404);
    if (before[0].plan_code === "lifetime_byok" && !hasRecentMFA(context, config)) {
      return context.json({ error: "recent_mfa_required" }, 403);
    }
    const rows = await database`
      update entitlement_grants set revoked_at = now(), updated_at = now()
      where id = ${grantID}::uuid and revoked_at is null returning id, account_id, revoked_at
    `;
    if (!rows[0]) return context.json({ error: "grant_already_revoked" }, 409);
    await audit(database, context, "entitlements.revoke", "revoke_grant", "grant", grantID, body.reason, before[0], rows[0]);
    return context.body(null, 204);
  });

  app.post("/v1/admin/devices/:id/revoke", requireRoles("owner", "support"), async (context) => {
    const deviceID = uuidSchema.parse(context.req.param("id"));
    const body = z.object({ reason: reasonSchema }).parse(await context.req.json());
    const rows = await database`
      update devices set revoked_at = now() where id = ${deviceID}::uuid and revoked_at is null
      returning id, account_id, revoked_at
    `;
    if (!rows[0]) return context.json({ error: "device_not_found" }, 404);
    await audit(database, context, "devices.revoke", "revoke_device", "device", deviceID, body.reason, null, rows[0]);
    return context.body(null, 204);
  });

  app.post("/v1/admin/users/:id/sign-out", requireRoles("owner", "support"), async (context) => {
    const accountID = uuidSchema.parse(context.req.param("id"));
    const body = z.object({ reason: reasonSchema }).parse(await context.req.json());
    const accounts = await database`select auth_subject from accounts where id = ${accountID}::uuid and deleted_at is null`;
    if (!accounts[0]?.auth_subject) return context.json({ error: "user_not_found" }, 404);
    const subject = String(accounts[0].auth_subject);
    const betterAuthRows = await database`
      with deleted_access as (
        delete from auth_oauth_access_tokens where "userId" = ${subject} returning id
      ), deleted_refresh as (
        delete from auth_oauth_refresh_tokens where "userId" = ${subject} returning id
      ), deleted_sessions as (
        delete from auth_sessions where "userId" = ${subject} returning id
      )
      select
        (select count(*)::integer from deleted_sessions) as sessions,
        (select count(*)::integer from deleted_refresh) as refresh_tokens,
        (select count(*)::integer from deleted_access) as access_tokens
    `;
    let clerkSessions = 0;
    if (config.CLERK_SECRET_KEY) {
      const sessionsResponse = await fetch(`https://api.clerk.com/v1/sessions?user_id=${encodeURIComponent(subject)}&status=active&limit=100`, {
        headers: { Authorization: `Bearer ${config.CLERK_SECRET_KEY}` }
      });
      if (!sessionsResponse.ok) return context.json({ error: "identity_management_failed" }, 502);
      const sessionsPayload = await sessionsResponse.json() as { data?: Array<{ id: string }> } | Array<{ id: string }>;
      const sessions = Array.isArray(sessionsPayload) ? sessionsPayload : sessionsPayload.data ?? [];
      for (const session of sessions) {
        const response = await fetch(`https://api.clerk.com/v1/sessions/${encodeURIComponent(session.id)}/revoke`, {
          method: "POST", headers: { Authorization: `Bearer ${config.CLERK_SECRET_KEY}` }
        });
        if (!response.ok && response.status !== 404) return context.json({ error: "identity_management_failed" }, 502);
      }
      clerkSessions = sessions.length;
    }
    const revokedSessions = Number(betterAuthRows[0]?.sessions ?? 0) + clerkSessions;
    const result = {
      revokedSessions,
      betterAuthRefreshTokens: Number(betterAuthRows[0]?.refresh_tokens ?? 0),
      betterAuthAccessTokens: Number(betterAuthRows[0]?.access_tokens ?? 0),
      clerkSessions
    };
    await audit(database, context, "sessions.revoke", "sign_out_user", "account", accountID, body.reason, null, result);
    return context.json(result);
  });

  app.post("/v1/admin/users/:id/deletion-jobs", requireRoles("owner", "support"), async (context) => {
    if (!hasRecentMFA(context, config)) return context.json({ error: "recent_mfa_required" }, 403);
    const accountID = uuidSchema.parse(context.req.param("id"));
    const body = z.object({ reason: reasonSchema, confirmation: z.literal("DELETE") }).parse(await context.req.json());
    const rows = await database`
      insert into deletion_jobs (account_id, execute_after)
      select id, now() + interval '7 days' from accounts where id = ${accountID}::uuid and deleted_at is null
      on conflict (account_id) do update set requested_at = now(), execute_after = now() + interval '7 days', status = 'pending', completed_at = null
      returning id, account_id, requested_at, execute_after, status
    `;
    if (!rows[0]) return context.json({ error: "user_not_found" }, 404);
    await audit(database, context, "accounts.delete", "schedule_deletion", "account", accountID, body.reason, null, rows[0]);
    return context.json({ deletionJob: rows[0] }, 202);
  });

  app.get("/v1/admin/billing/events", requireRoles("owner", "billing", "viewer"), async (context) => {
    const status = context.req.query("status") ?? "";
    const rows = await database`
      select provider, provider_event_id, event_type, status, attempt_count,
             last_error_code, provider_created_at, processed_at
      from billing_events where (${status} = '' or status = ${status})
      order by processed_at desc limit 250
    `;
    return context.json({ events: rows });
  });

  app.post("/v1/admin/billing/reconcile", requireRoles("owner", "billing"), async (context) => {
    if (!stripe) return context.json({ error: "billing_not_configured" }, 503);
    const body = z.object({ accountID: z.string().uuid().optional(), reason: reasonSchema }).parse(await context.req.json());
    if (!body.accountID && context.get("adminRole") !== "owner") {
      return context.json({ error: "owner_required_for_global_reconciliation" }, 403);
    }
    const result = await reconcileStripeSubscriptions(database, stripe, body.accountID);
    await audit(
      database, context, "billing.reconcile", "reconcile_billing",
      body.accountID ? "account" : "billing", body.accountID ?? "all",
      body.reason, null, { scanned: result.scanned, reconciled: result.reconciled, failures: result.failures.length }
    );
    return context.json(result);
  });

  app.post("/v1/admin/billing/refunds", requireRoles("owner", "billing"), async (context) => {
    if (!hasRecentMFA(context, config)) return context.json({ error: "recent_mfa_required" }, 403);
    if (!stripe) return context.json({ error: "billing_not_configured" }, 503);
    const input = refundSchema.parse(await context.req.json());
    const paymentIntent = await stripe.paymentIntents.retrieve(input.paymentIntentID);
    const customerID = stripeIdentifier(paymentIntent.customer);
    if (!customerID) return context.json({ error: "payment_customer_not_found" }, 409);
    const accounts = await database`select account_id from billing_customers where stripe_customer_id = ${customerID}`;
    if (!accounts[0]?.account_id) return context.json({ error: "billing_customer_not_found" }, 404);
    const refund = await stripe.refunds.create({
      payment_intent: input.paymentIntentID,
      ...(input.amount ? { amount: input.amount } : {}),
      reason: "requested_by_customer",
      metadata: { account_id: String(accounts[0].account_id), admin_reason: input.reason.slice(0, 500) }
    }, { idempotencyKey: `admin-refund:${input.idempotencyKey}` });
    await audit(database, context, "billing.refund", "create_refund", "account", String(accounts[0].account_id), input.reason, null, {
      refundID: refund.id, amount: refund.amount, status: refund.status
    });
    return context.json({ refund: { id: refund.id, amount: refund.amount, status: refund.status } }, 201);
  });

  app.get("/v1/admin/campaigns", requireRoles("owner", "support", "billing", "viewer"), async (context) => {
    const rows = await database`
      select c.id, c.public_id, c.kind, c.code_hint, c.plan_code, c.duration_days,
             c.is_lifetime, c.discount_percent, c.discount_amount, c.currency,
             c.max_redemptions, c.starts_at, c.expires_at, c.status,
             c.restricted_email, c.restricted_domain, c.internal_note, c.created_at,
             count(r.id)::integer as redemptions
      from access_campaigns c left join access_redemptions r on r.campaign_id = c.id
      group by c.id order by c.created_at desc limit 500
    `;
    return context.json({ campaigns: rows });
  });

  app.patch("/v1/admin/campaigns/:id", requireRoles("owner", "support", "billing"), async (context) => {
    const campaignID = uuidSchema.parse(context.req.param("id"));
    const body = z.object({
      maxRedemptions: z.number().int().positive().max(100_000).optional(),
      expiresAt: z.string().datetime().nullable().optional(),
      internalNote: z.string().trim().max(2_000).nullable().optional(),
      status: z.enum(["draft", "active"]).optional(),
      reason: reasonSchema
    }).parse(await context.req.json());
    const before = await database`
      select id, kind, max_redemptions, expires_at, internal_note, status
      from access_campaigns where id = ${campaignID}::uuid
    `;
    if (!before[0]) return context.json({ error: "campaign_not_found" }, 404);
    if (before[0].kind === "stripe_discount"
      && (body.maxRedemptions !== undefined || body.expiresAt !== undefined || body.status !== undefined)) {
      return context.json({ error: "stripe_campaign_limits_immutable" }, 409);
    }
    const rows = await database`
      update access_campaigns set
        max_redemptions = coalesce(${body.maxRedemptions ?? null}, max_redemptions),
        expires_at = case when ${body.expiresAt === null} then null else coalesce(${body.expiresAt ?? null}::timestamptz, expires_at) end,
        internal_note = case when ${body.internalNote === null} then null else coalesce(${body.internalNote ?? null}, internal_note) end,
        status = coalesce(${body.status ?? null}, status),
        updated_at = now()
      where id = ${campaignID}::uuid and status <> 'revoked'
      returning id, public_id, max_redemptions, expires_at, internal_note, status
    `;
    if (!rows[0]) return context.json({ error: "campaign_not_editable" }, 409);
    await audit(database, context, "campaigns.update", "update_campaign", "campaign", campaignID, body.reason, before[0], rows[0]);
    return context.json({ campaign: rows[0] });
  });

  app.post("/v1/admin/campaigns", requireRoles("owner", "support", "billing"), async (context) => {
    if (!config.ACCESS_CAMPAIGNS_ENABLED) return context.json({ error: "feature_disabled" }, 404);
    const input = campaignSchema.parse(await context.req.json());
    if (input.kind === "stripe_discount" && !["owner", "billing"].includes(context.get("adminRole"))) {
      return context.json({ error: "insufficient_role" }, 403);
    }
    if (input.plan === "lifetime_byok") {
      if (context.get("adminRole") !== "owner") return context.json({ error: "insufficient_role" }, 403);
      if (!hasRecentMFA(context, config)) return context.json({ error: "recent_mfa_required" }, 403);
    }
    const rawSecret = input.delivery === "link"
      ? randomBytes(16).toString("base64url")
      : readableCode();
    const secretHash = createHash("sha256").update(normalizeCampaignSecret(rawSecret)).digest("hex");
    const publicID = `cmp_${randomUUID().replaceAll("-", "")}`;
    let stripePromotionCodeID: string | null = null;
    if (input.kind === "stripe_discount") {
      if (!stripe) return context.json({ error: "billing_not_configured" }, 503);
      const coupon = await stripe.coupons.create({
        ...(input.discountPercent ? { percent_off: input.discountPercent } : {}),
        ...(input.discountAmount ? { amount_off: input.discountAmount, currency: "eur" } : {}),
        duration: "once",
        max_redemptions: input.maxRedemptions,
        ...(input.expiresAt ? { redeem_by: Math.floor(new Date(input.expiresAt).getTime() / 1_000) } : {}),
        name: `Pressay ${rawSecret}`,
        metadata: { pressay_campaign_id: publicID }
      }, { idempotencyKey: `campaign-coupon:${publicID}` });
      try {
        const promotion = await stripe.promotionCodes.create({
          promotion: { type: "coupon", coupon: coupon.id },
          code: rawSecret,
          max_redemptions: input.maxRedemptions,
          ...(input.expiresAt ? { expires_at: Math.floor(new Date(input.expiresAt).getTime() / 1_000) } : {}),
          restrictions: { first_time_transaction: false },
          metadata: { pressay_campaign_id: publicID }
        }, { idempotencyKey: `campaign-promotion:${publicID}` });
        stripePromotionCodeID = promotion.id;
      } catch (error) {
        await stripe.coupons.del(coupon.id).catch(() => undefined);
        throw error;
      }
    }
    let rows;
    try {
      rows = await database`
        insert into access_campaigns (
          public_id, kind, code_hash, link_token_hash, code_hint, plan_code,
          duration_days, is_lifetime, discount_percent, discount_amount,
          max_redemptions, starts_at, expires_at, restricted_email,
          restricted_domain, internal_note, created_by, stripe_promotion_code_id
        ) values (
          ${publicID}, ${input.kind},
          ${input.delivery === "code" ? secretHash : null},
          ${input.delivery === "link" ? secretHash : null},
          ${input.delivery === "code" ? rawSecret.slice(-4) : null},
          ${input.kind === "access_grant" ? input.plan ?? null : null},
          ${input.plan === "lifetime_byok" ? null : input.durationDays ?? null},
          ${input.plan === "lifetime_byok"}, ${input.discountPercent ?? null},
          ${input.discountAmount ?? null}, ${input.maxRedemptions},
          ${input.startsAt ?? new Date().toISOString()}::timestamptz,
          ${input.expiresAt ?? null}::timestamptz,
          ${input.restrictedEmail?.toLowerCase() ?? null},
          ${input.restrictedDomain?.toLowerCase() ?? null},
          ${input.internalNote ?? null}, ${context.get("adminAccountID")}::uuid,
          ${stripePromotionCodeID}
        ) returning id, public_id, kind, plan_code, duration_days, is_lifetime, max_redemptions, starts_at, expires_at, status
      `;
    } catch (error) {
      if (stripe && stripePromotionCodeID) {
        await stripe.promotionCodes.update(stripePromotionCodeID, { active: false }).catch(() => undefined);
      }
      throw error;
    }
    await audit(database, context, "campaigns.create", "create_campaign", "campaign", String(rows[0]?.id), input.reason, null, rows[0] ?? {});
    return context.json({ campaign: rows[0], secret: rawSecret, delivery: input.delivery, secretShownOnce: true }, 201);
  });

  app.delete("/v1/admin/campaigns/:id", requireRoles("owner", "support", "billing"), async (context) => {
    const campaignID = uuidSchema.parse(context.req.param("id"));
    const body = z.object({ reason: reasonSchema }).parse(await context.req.json());
    const before = await database`
      select id, public_id, kind, status, stripe_promotion_code_id
      from access_campaigns where id = ${campaignID}::uuid and status <> 'revoked'
    `;
    if (!before[0]) return context.json({ error: "campaign_not_found" }, 404);
    if (typeof before[0].stripe_promotion_code_id === "string") {
      if (!stripe) return context.json({ error: "billing_not_configured" }, 503);
      await stripe.promotionCodes.update(before[0].stripe_promotion_code_id, { active: false });
    }
    const rows = await database`
      update access_campaigns set status = 'revoked', updated_at = now()
      where id = ${campaignID}::uuid and status <> 'revoked'
      returning id, public_id, kind, status, stripe_promotion_code_id
    `;
    if (!rows[0]) return context.json({ error: "campaign_not_found" }, 404);
    await audit(database, context, "campaigns.revoke", "revoke_campaign", "campaign", campaignID, body.reason, before[0], rows[0]);
    return context.body(null, 204);
  });

  app.get("/v1/admin/referrals", requireRoles("owner", "support", "billing", "viewer"), async (context) => {
    const rows = await database`
      select ra.id, ra.referrer_account_id, ra.referee_account_id, ra.status,
             ra.source, ra.risk_status, ra.rejection_reason,
             ra.attributed_at, ra.expires_at, rc.code,
             count(rr.id)::integer as reward_count,
             count(rr.id) filter (where rr.status = 'pending')::integer as pending_rewards,
             count(rr.id) filter (where rr.status = 'applied')::integer as applied_rewards,
             count(rr.id) filter (where rr.status = 'failed')::integer as failed_rewards,
             max(rr.last_error_code) filter (where rr.status = 'failed') as last_error_code,
             max(rr.last_attempt_at) as last_attempt_at
      from referral_attributions ra
      join referral_codes rc on rc.account_id = ra.referrer_account_id
      left join referral_rewards rr on rr.attribution_id = ra.id
      group by ra.id, rc.code order by ra.attributed_at desc limit 500
    `;
    return context.json({ referrals: rows });
  });

  app.patch("/v1/admin/referrals/:id/risk", requireRoles("owner", "support"), async (context) => {
    const attributionID = uuidSchema.parse(context.req.param("id"));
    const body = z.object({ riskStatus: z.enum(["clear", "review", "blocked"]), reason: reasonSchema }).parse(await context.req.json());
    const before = await database`select id, status, risk_status from referral_attributions where id = ${attributionID}::uuid`;
    if (!before[0]) return context.json({ error: "referral_not_found" }, 404);
    if (before[0].status === "rewarded" && body.riskStatus === "blocked") {
      return context.json({ error: "refund_or_dispute_required_to_reverse_applied_rewards" }, 409);
    }
    const rows = await database`
      update referral_attributions set risk_status = ${body.riskStatus},
             status = case when ${body.riskStatus} = 'blocked' and status in ('attributed', 'qualified') then 'rejected' else status end,
             rejection_reason = case when ${body.riskStatus} = 'blocked' then ${body.reason} else rejection_reason end
      where id = ${attributionID}::uuid
      returning id, status, risk_status, rejection_reason
    `;
    await audit(database, context, "referrals.risk", "review_referral", "referral", attributionID, body.reason, before[0], rows[0]);
    return context.json({ referral: rows[0] });
  });

  app.post("/v1/admin/referrals/:id/retry", requireRoles("owner", "billing"), async (context) => {
    if (!config.REFERRALS_ENABLED) return context.json({ error: "feature_disabled" }, 404);
    if (!hasRecentMFA(context, config)) return context.json({ error: "recent_mfa_required" }, 403);
    if (!stripe) return context.json({ error: "billing_not_configured" }, 503);
    const attributionID = uuidSchema.parse(context.req.param("id"));
    const body = z.object({ reason: reasonSchema }).parse(await context.req.json());
    const failedRewards = await database`
      select distinct provider_event_id
      from referral_rewards
      where attribution_id = ${attributionID}::uuid and status = 'failed'
    `;
    if (failedRewards.length === 0) return context.json({ error: "failed_reward_not_found" }, 404);
    let replayed = 0;
    for (const reward of failedRewards) {
      const event = await stripe.events.retrieve(String(reward.provider_event_id));
      if (await processReferralStripeEvent(database, stripe, config, event)) replayed += 1;
    }
    await audit(
      database, context, "referrals.retry", "retry_referral_reward", "referral",
      attributionID, body.reason, { failedEvents: failedRewards.length }, { replayed }
    );
    return context.json({ replayed });
  });

  app.post("/v1/admin/users/:id/notes", requireRoles("owner", "support"), async (context) => {
    const accountID = uuidSchema.parse(context.req.param("id"));
    const body = z.object({
      category: z.enum(["general", "billing", "technical", "privacy", "security"]),
      body: z.string().trim().min(1).max(4_000),
      reason: reasonSchema
    }).parse(await context.req.json());
    const rows = await database`
      insert into support_notes (account_id, category, body, created_by)
      select id, ${body.category}, ${body.body}, ${context.get("adminAccountID")}::uuid
      from accounts where id = ${accountID}::uuid and deleted_at is null
      returning id, account_id, category, body, created_at
    `;
    if (!rows[0]) return context.json({ error: "user_not_found" }, 404);
    await audit(database, context, "support.notes", "create_support_note", "account", accountID, body.reason, null, { noteID: rows[0].id, category: rows[0].category });
    return context.json({ note: rows[0], reminder: "Never paste dictation, audio, clipboard contents, API keys, or user files." }, 201);
  });

  app.delete("/v1/admin/notes/:id", requireRoles("owner", "support"), async (context) => {
    const noteID = uuidSchema.parse(context.req.param("id"));
    const body = z.object({ reason: reasonSchema }).parse(await context.req.json());
    const rows = await database`
      update support_notes set deleted_at = now() where id = ${noteID}::uuid and deleted_at is null
      returning id, account_id, category, deleted_at
    `;
    if (!rows[0]) return context.json({ error: "note_not_found" }, 404);
    await audit(database, context, "support.notes", "delete_support_note", "note", noteID, body.reason, null, rows[0]);
    return context.body(null, 204);
  });

  app.get("/v1/admin/memberships", requireRoles("owner"), async (context) => {
    const rows = await database`
      select m.account_id, m.role, m.status, m.created_at, m.disabled_at,
             a.email, a.display_name
      from admin_memberships m join accounts a on a.id = m.account_id
      order by m.created_at
    `;
    return context.json({ memberships: rows });
  });

  app.post("/v1/admin/memberships", requireRoles("owner"), async (context) => {
    if (!hasRecentMFA(context, config)) return context.json({ error: "recent_mfa_required" }, 403);
    const body = z.object({ accountID: z.string().uuid(), role: z.enum(adminRoles), reason: reasonSchema }).parse(await context.req.json());
    if (body.role === "owner") return context.json({ error: "owner_transfer_requires_dedicated_recovery_process" }, 409);
    const rows = await database`
      insert into admin_memberships (account_id, role, status, granted_by)
      select id, ${body.role}, 'active', ${context.get("adminAccountID")}::uuid
      from accounts where id = ${body.accountID}::uuid and deleted_at is null
      on conflict (account_id) do update
      set role = excluded.role, status = 'active', disabled_at = null, granted_by = excluded.granted_by
      returning account_id, role, status, created_at
    `;
    if (!rows[0]) return context.json({ error: "user_not_found" }, 404);
    await audit(database, context, "admin.roles", "grant_admin_role", "account", body.accountID, body.reason, null, rows[0]);
    return context.json({ membership: rows[0] }, 201);
  });

  app.delete("/v1/admin/memberships/:accountID", requireRoles("owner"), async (context) => {
    if (!hasRecentMFA(context, config)) return context.json({ error: "recent_mfa_required" }, 403);
    const accountID = uuidSchema.parse(context.req.param("accountID"));
    const body = z.object({ reason: reasonSchema }).parse(await context.req.json());
    if (accountID === context.get("adminAccountID")) return context.json({ error: "owner_cannot_disable_self" }, 409);
    const rows = await database`
      update admin_memberships set status = 'disabled', disabled_at = now()
      where account_id = ${accountID}::uuid and role <> 'owner' and status = 'active'
      returning account_id, role, status, disabled_at
    `;
    if (!rows[0]) return context.json({ error: "membership_not_found_or_protected" }, 404);
    await audit(database, context, "admin.roles", "disable_admin_role", "account", accountID, body.reason, null, rows[0]);
    return context.body(null, 204);
  });

  app.get("/v1/admin/audit-log", requireRoles("owner", "viewer"), async (context) => {
    const rows = await database`
      select id, actor_account_id, actor_role, permission, action, target_type,
             target_id, reason, request_id, before_state, after_state, result, created_at
      from admin_audit_log order by created_at desc limit 500
    `;
    return context.json({ entries: rows });
  });
}

function adminAuthentication(config: AppConfig, database: Database): MiddlewareHandler<{ Variables: AdminVariables }> {
  return async (context, next) => {
    if (!config.ADMIN_ENABLED) return context.json({ error: "not_found" }, 404);
    const subject = context.get("authSubject");
    const verifiedEmail = context.get("authEmail")?.trim().toLowerCase();
    if (verifiedEmail === config.PRESSAY_OWNER_EMAIL.toLowerCase()) {
      await database`
        insert into admin_memberships (account_id, role, status, granted_by)
        select a.id, 'owner', 'active', a.id
        from accounts a
        where a.auth_subject = ${subject}
          and a.deleted_at is null
          and lower(a.email) = ${verifiedEmail}
          and not exists (
            select 1 from admin_memberships where role = 'owner'
          )
        on conflict (account_id) do nothing
      `;
    }
    const rows = await database`
      select a.id as account_id, m.role
      from accounts a join admin_memberships m on m.account_id = a.id
      where a.auth_subject = ${subject} and a.deleted_at is null and m.status = 'active'
      limit 1
    `;
    const membership = rows[0];
    const role = membership?.role;
    if (!membership || !adminRoles.includes(role as AdminRole)) return context.json({ error: "admin_access_denied" }, 403);
    context.set("adminAccountID", String(membership.account_id));
    context.set("adminRole", role as AdminRole);
    await next();
  };
}

function requireRoles(...roles: AdminRole[]): MiddlewareHandler<{ Variables: AdminVariables }> {
  return async (context, next) => {
    if (!roles.includes(context.get("adminRole"))) return context.json({ error: "insufficient_role" }, 403);
    await next();
  };
}

function hasRecentMFA(context: {
  get(key: "authFactorVerificationAge"): readonly [number, number] | undefined;
  get(key: "authStepUpAt"): number | undefined;
}, config: AppConfig): boolean {
  return hasRecentStrongAuthentication(
    context.get("authFactorVerificationAge"),
    context.get("authStepUpAt"),
    config.PRESSAY_ADMIN_MFA_MAX_AGE_MINUTES
  );
}

async function audit(
  database: Database,
  context: { get(key: "adminAccountID" | "adminRole" | "requestID"): string },
  permission: string,
  action: string,
  targetType: string,
  targetID: string,
  reason: string,
  beforeState: unknown,
  afterState: unknown
): Promise<void> {
  await database`
    insert into admin_audit_log (
      actor_account_id, actor_role, permission, action, target_type, target_id,
      reason, request_id, before_state, after_state, result
    ) values (
      ${context.get("adminAccountID")}::uuid, ${context.get("adminRole")},
      ${permission}, ${action}, ${targetType}, ${targetID}, ${reason},
      ${context.get("requestID")}, ${JSON.stringify(redactState(beforeState))}::jsonb,
      ${JSON.stringify(redactState(afterState))}::jsonb, 'success'
    )
  `;
}

function redactState(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object") return {};
  const forbidden = /audio|transcript|text|selection|clipboard|prompt|api.?key|secret|token|cipher/i;
  return Object.fromEntries(Object.entries(value).filter(([key]) => !forbidden.test(key)).slice(0, 100));
}

function readableCode(): string {
  const alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
  const bytes = randomBytes(10);
  return Array.from(bytes, (byte) => alphabet[byte % alphabet.length]).join("");
}

function normalizeCampaignSecret(value: string): string {
  return value.trim().toUpperCase().replaceAll(/[^A-Z0-9_-]/g, "");
}

function csvCell(value: unknown): string {
  const raw = value == null ? "" : String(value);
  return `"${raw.replaceAll('"', '""')}"`;
}

function stripeIdentifier(value: string | { id: string } | null): string | null {
  if (!value) return null;
  return typeof value === "string" ? value : value.id;
}
