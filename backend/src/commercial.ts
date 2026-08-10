import { createHash, createHmac } from "node:crypto";
import type { Hono } from "hono";
import type Stripe from "stripe";
import { z } from "zod";
import type { AdminVariables } from "./admin.js";
import type { AppConfig } from "./config.js";
import type { Database } from "./db.js";

const claimSchema = z.object({
  secret: z.string().trim().min(6).max(256),
  delivery: z.enum(["code", "link"])
});

const attributionSchema = z.object({
  code: z.string().trim().min(6).max(16)
});

export function registerCommercialRoutes(
  app: Hono<{ Variables: AdminVariables }>,
  config: AppConfig,
  database: Database
): void {
  app.post("/v1/access/claim", async (context) => {
    if (!config.ACCESS_CAMPAIGNS_ENABLED) return context.json({ error: "feature_disabled" }, 404);
    const input = claimSchema.parse(await context.req.json());
    const normalized = normalizeSecret(input.secret);
    const hash = createHash("sha256").update(normalized).digest("hex");
    const subject = context.get("authSubject");
    const rows = await database`
      with account as (
        select a.id, lower(coalesce(a.email, '')) as email,
               split_part(lower(coalesce(a.email, '')), '@', 2) as email_domain
        from accounts a
        where a.auth_subject = ${subject} and a.deleted_at is null
      ), campaign as (
        select c.*, pg_advisory_xact_lock(hashtextextended(c.id::text, 0))
        from access_campaigns c
        where c.status = 'active'
          and c.kind = 'access_grant'
          and c.starts_at <= now()
          and (c.expires_at is null or c.expires_at > now())
          and case when ${input.delivery} = 'code' then c.code_hash = ${hash}
                   else c.link_token_hash = ${hash} end
        limit 1
      ), eligible as (
        select a.id as account_id, c.id as campaign_id, c.plan_code,
               c.duration_days, c.is_lifetime
        from account a cross join campaign c
        where (c.restricted_email is null or lower(c.restricted_email) = a.email)
          and (c.restricted_domain is null or lower(c.restricted_domain) = a.email_domain)
          and not exists (
            select 1 from admin_memberships m where m.account_id = a.id and m.status = 'active'
          )
          and not exists (
            select 1 from entitlements e
            where e.account_id = a.id
              and (e.plan_code = 'lifetime_byok' or e.founding_claimed_at is not null or e.source = 'legacy')
              and e.status in ('active', 'trialing')
          )
          and not exists (
            select 1 from entitlement_grants g
            where g.account_id = a.id and g.plan_code = 'lifetime_byok'
              and g.revoked_at is null and (g.ends_at is null or g.ends_at > now())
          )
          and (select count(*) from access_redemptions r where r.campaign_id = c.id) < c.max_redemptions
      ), redeemed as (
        insert into access_redemptions (campaign_id, account_id)
        select campaign_id, account_id from eligible
        on conflict (campaign_id, account_id) do nothing
        returning id, campaign_id, account_id
      ), granted as (
        insert into entitlement_grants (
          account_id, plan_code, source, starts_at, ends_at, campaign_id, reason, metadata
        )
        select r.account_id, e.plan_code, 'admin_code', now(),
               case when e.is_lifetime then null else now() + (e.duration_days * interval '1 day') end,
               r.campaign_id, 'Access campaign redemption',
               jsonb_build_object('redemption_id', r.id)
        from redeemed r join eligible e on e.account_id = r.account_id and e.campaign_id = r.campaign_id
        returning id, account_id, plan_code, starts_at, ends_at, campaign_id
      ), linked as (
        update access_redemptions r set grant_id = g.id
        from granted g where r.campaign_id = g.campaign_id and r.account_id = g.account_id
        returning r.id
      )
      select * from granted
    `;
    if (!rows[0]) {
      const already = await database`
        select r.id from access_redemptions r
        join accounts a on a.id = r.account_id
        join access_campaigns c on c.id = r.campaign_id
        where a.auth_subject = ${subject}
          and case when ${input.delivery} = 'code' then c.code_hash = ${hash}
                   else c.link_token_hash = ${hash} end
        limit 1
      `;
      return context.json({ error: already[0] ? "campaign_already_redeemed" : "campaign_invalid_or_ineligible" }, 409);
    }
    return context.json({ grant: rows[0], stacking: "most_favorable_end_date" }, 201);
  });

  app.get("/v1/referrals/me", async (context) => {
    if (!config.REFERRALS_ENABLED) return context.json({ error: "feature_disabled" }, 404);
    const subject = context.get("authSubject");
    const accounts = await database`
      select id from accounts where auth_subject = ${subject} and deleted_at is null limit 1
    `;
    if (!accounts[0]?.id) return context.json({ error: "account_not_provisioned" }, 404);
    const accountID = String(accounts[0].id);
    const code = stableReferralCode(accountID);
    await database`
      insert into referral_codes (account_id, code)
      values (${accountID}::uuid, ${code})
      on conflict (account_id) do nothing
    `;
    const [codes, funnel, rewards] = await Promise.all([
      database`select code, created_at, disabled_at from referral_codes where account_id = ${accountID}::uuid`,
      database`
        select count(*)::integer as signups,
               count(*) filter (where status in ('qualified', 'rewarded'))::integer as conversions
        from referral_attributions where referrer_account_id = ${accountID}::uuid
      `,
      database`
        select id, side, reward_kind, status, campaign_id, applied_at, reversed_at, created_at
        from referral_rewards where beneficiary_account_id = ${accountID}::uuid order by created_at desc
      `
    ]);
    return context.json({
      code: codes[0]?.code,
      link: `https://press-say.app/r/${codes[0]?.code}`,
      signups: Number(funnel[0]?.signups ?? 0),
      conversions: Number(funnel[0]?.conversions ?? 0),
      rewards: rewards.map((reward) => ({
        ...reward,
        ...(reward.reward_kind === "guest_pass" && reward.status === "applied"
          ? { guestPassLink: `https://press-say.app/access/${guestPassSecret(config, String(reward.id))}` }
          : {})
      })),
      terms: { rewardDays: 30, trigger: "first_paid_subscription_invoice", lifetimePurchasesEligible: false }
    });
  });

  app.post("/v1/referrals/attribute", async (context) => {
    if (!config.REFERRALS_ENABLED) return context.json({ error: "feature_disabled" }, 404);
    const input = attributionSchema.parse(await context.req.json());
    const code = input.code.toUpperCase();
    const subject = context.get("authSubject");
    const rows = await database`
      with referee as (
        select a.id, a.created_at
        from accounts a
        where a.auth_subject = ${subject} and a.deleted_at is null
      ), referral as (
        select rc.account_id as referrer_account_id, rc.code
        from referral_codes rc where rc.code = ${code} and rc.disabled_at is null
      ), eligible as (
        select r.referrer_account_id, f.id as referee_account_id, r.code
        from referee f cross join referral r
        where r.referrer_account_id <> f.id
          and f.created_at >= now() - interval '24 hours'
          and not exists (select 1 from billing_customers b where b.account_id = f.id and (b.stripe_customer_id is not null or b.app_store_original_transaction_id is not null))
          and not exists (select 1 from founding_claims fc where fc.account_id = f.id)
          and not exists (select 1 from entitlements e where e.account_id = f.id and e.plan_code = 'lifetime_byok')
          and not exists (
            select 1 from devices rd join devices fd on fd.device_identifier = rd.device_identifier
            where rd.account_id = r.referrer_account_id and fd.account_id = f.id
          )
      )
      insert into referral_attributions (
        referrer_account_id, referee_account_id, referral_code, source, expires_at
      )
      select referrer_account_id, referee_account_id, code, 'link', now() + interval '30 days'
      from eligible
      on conflict (referee_account_id) do nothing
      returning id, referrer_account_id, referee_account_id, status, attributed_at, expires_at
    `;
    if (!rows[0]) return context.json({ error: "referral_invalid_or_already_attributed" }, 409);
    return context.json({ attribution: rows[0] }, 201);
  });
}

export async function processReferralStripeEvent(
  database: Database,
  stripe: Stripe,
  config: AppConfig,
  event: Stripe.Event
): Promise<boolean> {
  if (!config.REFERRALS_ENABLED) return false;
  if (event.type === "invoice.paid") {
    return applyPaidInvoiceRewards(database, stripe, config, event);
  }
  if (event.type === "charge.refunded" || event.type === "charge.dispute.created") {
    return reverseReferralRewards(database, stripe, event);
  }
  return false;
}

async function applyPaidInvoiceRewards(
  database: Database,
  stripe: Stripe,
  config: AppConfig,
  event: Stripe.Event
): Promise<boolean> {
  const invoice = event.data.object as Stripe.Invoice;
  if (invoice.amount_paid <= 0) return false;
  const customerID = stripeID(invoice.customer);
  const subscriptionID = invoiceSubscriptionID(invoice);
  if (!customerID || !subscriptionID) return false;

  const paidInvoices = await stripe.invoices.list({ customer: customerID, status: "paid", limit: 100 });
  const firstPaid = paidInvoices.data
    .filter((candidate) => candidate.amount_paid > 0 && invoiceSubscriptionID(candidate) === subscriptionID)
    .sort((left, right) => left.created - right.created)[0];
  if (!firstPaid || firstPaid.id !== invoice.id) return false;

  const attributions = await database`
    select ra.id, ra.referrer_account_id, ra.referee_account_id
    from referral_attributions ra
    join billing_customers bc on bc.account_id = ra.referee_account_id
    where bc.stripe_customer_id = ${customerID}
      and ra.status = 'attributed'
      and ra.expires_at > now()
      and not exists (
        select 1 from devices rd join devices fd on fd.device_identifier = rd.device_identifier
        where rd.account_id = ra.referrer_account_id and fd.account_id = ra.referee_account_id
      )
    limit 1
  `;
  const attribution = attributions[0];
  if (!attribution) return false;
  const attributionID = String(attribution.id);
  const referrerID = String(attribution.referrer_account_id);
  const refereeID = String(attribution.referee_account_id);

  const referrerState = await database`
    select e.plan_code, e.status, e.source, e.founding_claimed_at,
           b.stripe_subscription_id
    from accounts a
    left join entitlements e on e.account_id = a.id
    left join billing_customers b on b.account_id = a.id
    where a.id = ${referrerID}::uuid
  `;
  const referrer = referrerState[0] ?? {};
  const referrerIsLifetime = referrer.plan_code === "lifetime_byok"
    || referrer.founding_claimed_at != null
    || referrer.source === "legacy";
  const referrerHasSubscription = typeof referrer.stripe_subscription_id === "string"
    && ["active", "trialing"].includes(String(referrer.status));
  const referrerRewardKind = referrerIsLifetime
    ? "guest_pass"
    : referrerHasSubscription
      ? "billing_extension"
      : "access_grant";

  let rewards = await database`
    insert into referral_rewards (
      attribution_id, beneficiary_account_id, side, reward_kind,
      status, provider_event_id
    ) values
      (${attributionID}::uuid, ${referrerID}::uuid, 'referrer', ${referrerRewardKind}, 'pending', ${event.id}),
      (${attributionID}::uuid, ${refereeID}::uuid, 'referee', 'billing_extension', 'pending', ${event.id})
    on conflict (attribution_id, side, provider_event_id) do nothing
    returning id, beneficiary_account_id, side, reward_kind
  `;
  if (rewards.length === 0) {
    rewards = await database`
      select id, beneficiary_account_id, side, reward_kind
      from referral_rewards
      where attribution_id = ${attributionID}::uuid
        and provider_event_id = ${event.id}
        and status in ('pending', 'failed')
    `;
  }
  if (rewards.length === 0) return false;

  for (const reward of rewards) {
    const rewardID = String(reward.id);
    try {
      if (reward.reward_kind === "billing_extension") {
        const targetSubscriptionID = reward.side === "referee"
          ? subscriptionID
          : String(referrer.stripe_subscription_id);
        const subscription = await stripe.subscriptions.retrieve(targetSubscriptionID);
        const itemPeriodEnd = subscription.items.data
          .map((item) => item.current_period_end)
          .sort((left, right) => right - left)[0] ?? Math.floor(Date.now() / 1_000);
        const base = Math.max(itemPeriodEnd, subscription.trial_end ?? 0, Math.floor(Date.now() / 1_000));
        const appliedUntil = base + 30 * 86_400;
        await stripe.subscriptions.update(targetSubscriptionID, {
          trial_end: appliedUntil,
          proration_behavior: "none"
        }, { idempotencyKey: `referral-reward:${rewardID}` });
        await database`
          update referral_rewards set status = 'applied', applied_at = now(),
                 applied_subscription_id = ${targetSubscriptionID},
                 applied_until = ${new Date(appliedUntil * 1_000).toISOString()}::timestamptz,
                 last_error_code = null
          where id = ${rewardID}::uuid
        `;
      } else if (reward.reward_kind === "access_grant") {
        const grants = await database`
          insert into entitlement_grants (
            account_id, plan_code, source, starts_at, ends_at, reason, metadata
          ) values (
            ${String(reward.beneficiary_account_id)}::uuid, 'pro_byok', 'referral',
            now(), now() + interval '30 days', 'Referral reward',
            jsonb_build_object('reward_id', ${rewardID})
          ) returning id, ends_at
        `;
        await database`
          update referral_rewards set status = 'applied', applied_at = now(),
                 grant_id = ${String(grants[0]?.id)}::uuid,
                 applied_until = ${String(grants[0]?.ends_at)}::timestamptz,
                 last_error_code = null
          where id = ${rewardID}::uuid
        `;
      } else {
        const secret = guestPassSecret(config, rewardID);
        const secretHash = createHash("sha256").update(normalizeSecret(secret)).digest("hex");
        const campaigns = await database`
          insert into access_campaigns (
            public_id, kind, link_token_hash, plan_code, duration_days,
            max_redemptions, starts_at, expires_at, status, internal_note, created_by
          ) values (
            ${`ref_${rewardID.replaceAll("-", "")}`}, 'access_grant', ${secretHash},
            'pro_byok', 30, 1, now(), now() + interval '365 days', 'active',
            'Transferable guest pass generated by a Lifetime referral reward',
            ${String(reward.beneficiary_account_id)}::uuid
          ) returning id
        `;
        await database`
          update referral_rewards set status = 'applied', applied_at = now(),
                 campaign_id = ${String(campaigns[0]?.id)}::uuid,
                 last_error_code = null
          where id = ${rewardID}::uuid
        `;
      }
    } catch (error) {
      await database`
        update referral_rewards set status = 'failed',
               last_error_code = ${error instanceof Error ? error.name.slice(0, 100) : "unknown"}
        where id = ${rewardID}::uuid
      `;
      throw error;
    }
  }
  await database`
    update referral_attributions set status = 'rewarded'
    where id = ${attributionID}::uuid
      and not exists (select 1 from referral_rewards where attribution_id = ${attributionID}::uuid and status <> 'applied')
  `;
  return true;
}

async function reverseReferralRewards(
  database: Database,
  stripe: Stripe,
  event: Stripe.Event
): Promise<boolean> {
  const charge = event.data.object as Stripe.Charge | Stripe.Dispute;
  if (event.type === "charge.refunded") {
    const refundedCharge = charge as Stripe.Charge;
    if (refundedCharge.amount_refunded < refundedCharge.amount) return false;
  }
  const customerID = event.type === "charge.refunded"
    ? stripeID((charge as Stripe.Charge).customer)
    : await disputeCustomerID(stripe, charge as Stripe.Dispute);
  if (!customerID) return false;
  const rewards = await database`
    select rr.id, rr.reward_kind, rr.grant_id, rr.campaign_id,
           rr.applied_subscription_id, rr.applied_until, ra.id as attribution_id
    from referral_attributions ra
    join billing_customers bc on bc.account_id = ra.referee_account_id
    join referral_rewards rr on rr.attribution_id = ra.id
    where bc.stripe_customer_id = ${customerID} and rr.status = 'applied'
  `;
  for (const reward of rewards) {
    if (reward.grant_id) {
      await database`
        update entitlement_grants set revoked_at = now(), updated_at = now()
        where id = ${String(reward.grant_id)}::uuid and revoked_at is null and (ends_at is null or ends_at > now())
      `;
    }
    if (reward.campaign_id) {
      await database`
        update access_campaigns set status = 'revoked', updated_at = now()
        where id = ${String(reward.campaign_id)}::uuid and status = 'active'
      `;
    }
    if (typeof reward.applied_subscription_id === "string" && new Date(String(reward.applied_until)).getTime() > Date.now()) {
      await stripe.subscriptions.update(reward.applied_subscription_id, {
        trial_end: "now",
        proration_behavior: "none"
      }, { idempotencyKey: `referral-reversal:${String(reward.id)}:${event.id}` });
    }
    await database`
      update referral_rewards set status = 'reversed', reversed_at = now()
      where id = ${String(reward.id)}::uuid
    `;
  }
  if (rewards[0]?.attribution_id) {
    await database`update referral_attributions set status = 'reversed' where id = ${String(rewards[0].attribution_id)}::uuid`;
  }
  return rewards.length > 0;
}

function normalizeSecret(value: string): string {
  return value.trim().toUpperCase().replaceAll(/[^A-Z0-9_-]/g, "");
}

function stableReferralCode(accountID: string): string {
  return `P${createHash("sha256").update(`pressay:${accountID}`).digest("hex").slice(0, 10).toUpperCase()}`;
}

function guestPassSecret(config: AppConfig, rewardID: string): string {
  if (!config.PRESSAY_REFERRAL_COOKIE_SECRET) {
    throw new Error("referral_cookie_secret_not_configured");
  }
  return createHmac("sha256", config.PRESSAY_REFERRAL_COOKIE_SECRET)
    .update(`guest-pass:${rewardID}`)
    .digest("base64url")
    .slice(0, 24);
}

function stripeID(value: string | { id: string } | null): string | null {
  if (!value) return null;
  return typeof value === "string" ? value : value.id;
}

function invoiceSubscriptionID(invoice: Stripe.Invoice): string | null {
  const parent = invoice.parent as unknown as {
    subscription_details?: { subscription?: string | { id: string } | null }
  } | null;
  return stripeID(parent?.subscription_details?.subscription ?? null);
}

async function disputeCustomerID(stripe: Stripe, dispute: Stripe.Dispute): Promise<string | null> {
  const chargeID = stripeID(dispute.charge);
  if (!chargeID) return null;
  const charge = await stripe.charges.retrieve(chargeID);
  return "deleted" in charge && charge.deleted ? null : stripeID(charge.customer);
}
