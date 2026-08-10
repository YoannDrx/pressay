import { createHash } from "node:crypto";
import Stripe from "stripe";
import { z } from "zod";
import type { AppConfig } from "./config.js";
import type { Database } from "./db.js";
import type { PlanCode } from "./entitlements.js";

export const purchasablePlans = [
  "pro_byok",
  "lifetime_byok"
] as const;
export type PurchasablePlan = (typeof purchasablePlans)[number];
export type BillingInterval = "monthly" | "annual" | "lifetime";

type CheckoutSessionInput = {
  customerID: string;
  priceID: string;
  metadata: {
    account_id: string;
    plan_code: PurchasablePlan;
    device_id?: string;
    consent_id?: string;
  };
  interval: BillingInterval;
  trialEligible: boolean;
  successURL: string;
  cancelURL: string;
};

export const checkoutInputSchema = z.object({
  plan: z.enum(purchasablePlans),
  interval: z.enum(["monthly", "annual", "lifetime"]),
  deviceID: z.string().uuid().optional(),
  idempotencyKey: z.string().uuid(),
  acceptedTerms: z.literal(true),
  immediatePerformanceConsent: z.literal(true),
  termsVersion: z.literal("2026-08-10")
}).superRefine((value, context) => {
  const lifetimePlan = value.plan === "lifetime_byok";
  if (lifetimePlan !== (value.interval === "lifetime")) {
    context.addIssue({
      code: "custom",
      message: "lifetime_byok requires the lifetime interval"
    });
  }
});

export type StripeEventProjection = {
  accountID: string;
  plan: PlanCode;
  status: "active" | "trialing" | "past_due" | "canceled";
  stripeCustomerID: string | null;
  stripeSubscriptionID: string | null;
  subscriptionInterval: "monthly" | "annual" | null;
  subscriptionUnitAmount: number | null;
  currency: string | null;
  currentPeriodEnd: Date | null;
  trialEnd: Date | null;
  trialDeviceID: string | null;
  eventCreatedAt: Date;
};

export function createStripeClient(secretKey: string): Stripe {
  return new Stripe(secretKey, {
    apiVersion: "2026-07-29.dahlia",
    typescript: true
  });
}

export function priceID(
  config: AppConfig,
  plan: PurchasablePlan,
  interval: BillingInterval
): string | undefined {
  if (plan === "lifetime_byok") {
    return interval === "lifetime"
      ? config.STRIPE_PRICE_LIFETIME_BYOK
      : undefined;
  }
  if (interval === "lifetime") return undefined;
  if (plan === "pro_byok") {
    return interval === "monthly"
      ? config.STRIPE_PRICE_PRO_BYOK_MONTHLY
      : config.STRIPE_PRICE_PRO_BYOK_ANNUAL;
  }
  return undefined;
}

export function checkoutSessionParameters(
  input: CheckoutSessionInput
): Stripe.Checkout.SessionCreateParams {
  const common = {
    customer: input.customerID,
    line_items: [{ price: input.priceID, quantity: 1 }],
    metadata: input.metadata,
    client_reference_id: input.metadata.account_id,
    automatic_tax: { enabled: true },
    billing_address_collection: "auto" as const,
    customer_update: {
      address: "auto" as const,
      name: "auto" as const
    },
    tax_id_collection: { enabled: true },
    allow_promotion_codes: true,
    consent_collection: { terms_of_service: "required" as const },
    branding_settings: {
      display_name: "Pressay",
      background_color: "#111015",
      button_color: "#5B6CFF",
      border_style: "rounded" as const,
      font_family: "inter" as const
    },
    success_url: input.successURL,
    cancel_url: input.cancelURL
  };

  if (input.interval === "lifetime") {
    return {
      ...common,
      mode: "payment",
      payment_intent_data: { metadata: input.metadata }
    };
  }

  return {
    ...common,
    mode: "subscription",
    subscription_data: input.trialEligible
      ? {
          metadata: input.metadata,
          trial_period_days: 14,
          trial_settings: {
            end_behavior: { missing_payment_method: "cancel" }
          }
        }
      : { metadata: input.metadata },
    ...(input.trialEligible
      ? { payment_method_collection: "if_required" as const }
      : {})
  };
}

export function eventProjection(event: Stripe.Event): StripeEventProjection | null {
  if (
    event.type === "checkout.session.completed" ||
    event.type === "checkout.session.async_payment_succeeded"
  ) {
    const session = event.data.object;
    const accountID = session.metadata?.account_id;
    const plan = parsePlan(session.metadata?.plan_code);
    if (!accountID || !plan) return null;
    // Subscription lifecycle events are the source of truth for Pro. For the
    // one-time Lifetime offer, never grant an entitlement before Stripe marks
    // the Checkout payment as paid (important for asynchronous methods).
    if (plan !== "lifetime_byok" || session.payment_status !== "paid") {
      return null;
    }
    return {
      accountID,
      plan,
      status: "active",
      stripeCustomerID: stripeID(session.customer),
      stripeSubscriptionID: null,
      subscriptionInterval: null,
      subscriptionUnitAmount: null,
      currency: session.currency ?? null,
      currentPeriodEnd: null,
      trialEnd: null,
      trialDeviceID: session.metadata?.device_id ?? null,
      eventCreatedAt: new Date(event.created * 1_000)
    };
  }

  if (
    event.type === "customer.subscription.created" ||
    event.type === "customer.subscription.updated" ||
    event.type === "customer.subscription.deleted" ||
    event.type === "customer.subscription.paused" ||
    event.type === "customer.subscription.resumed"
  ) {
    const subscription = event.data.object;
    const accountID = subscription.metadata.account_id;
    const plan = parsePlan(subscription.metadata.plan_code);
    if (!accountID || !plan) return null;
    const periodEnd = subscription.items.data
      .map((item) => item.current_period_end)
      .filter((value): value is number => typeof value === "number")
      .sort((left, right) => right - left)[0]
      ?? (subscription as Stripe.Subscription & { current_period_end?: number }).current_period_end;
    const price = subscription.items.data[0]?.price;
    return {
      accountID,
      plan,
      status: event.type === "customer.subscription.deleted"
        ? "canceled"
        : subscriptionStatus(subscription.status),
      stripeCustomerID: stripeID(subscription.customer),
      stripeSubscriptionID: subscription.id,
      subscriptionInterval: price?.recurring?.interval === "month"
        ? "monthly"
        : price?.recurring?.interval === "year"
          ? "annual"
          : null,
      subscriptionUnitAmount: price?.unit_amount ?? null,
      currency: price?.currency ?? subscription.currency ?? null,
      currentPeriodEnd: periodEnd ? new Date(periodEnd * 1_000) : null,
      trialEnd: subscription.trial_end
        ? new Date(subscription.trial_end * 1_000)
        : null,
      trialDeviceID: subscription.metadata.device_id ?? null,
      eventCreatedAt: new Date(event.created * 1_000)
    };
  }

  if (event.type === "charge.refunded") {
    const charge = event.data.object;
    if (charge.amount_refunded < charge.amount) return null;
    const accountID = charge.metadata.account_id;
    const plan = parsePlan(charge.metadata.plan_code);
    if (!accountID || !plan) return null;
    return {
      accountID,
      plan,
      status: "canceled",
      stripeCustomerID: stripeID(charge.customer),
      stripeSubscriptionID: null,
      subscriptionInterval: null,
      subscriptionUnitAmount: null,
      currency: charge.currency,
      currentPeriodEnd: null,
      trialEnd: null,
      trialDeviceID: null,
      eventCreatedAt: new Date(event.created * 1_000)
    };
  }

  return null;
}

export async function persistStripeEvent(
  database: Database,
  event: Stripe.Event,
  rawBody: string
): Promise<boolean> {
  const payloadHash = createHash("sha256").update(rawBody).digest("hex");
  const inserted = await database`
    insert into billing_events (
      provider, provider_event_id, event_type, payload_sha256,
      status, attempt_count, provider_created_at
    ) values (
      'stripe', ${event.id}, ${event.type}, ${payloadHash}, 'processing', 1,
      ${new Date(event.created * 1_000).toISOString()}::timestamptz
    )
    on conflict (provider, provider_event_id) do update
    set status = 'processing',
        attempt_count = billing_events.attempt_count + 1,
        last_error_code = null,
        processed_at = null
    where billing_events.status = 'failed'
    returning provider_event_id
  `;
  if (!inserted[0]) return false;
  const transactionRecorded = await persistBillingTransaction(database, event);

  let projection = eventProjection(event);
  if (!projection && event.type === "charge.refunded") {
    const charge = event.data.object;
    const customerID = stripeID(charge.customer);
    if (charge.amount_refunded < charge.amount) {
      await markBillingEvent(database, event.id, "ignored", null);
      return false;
    }
    if (customerID) {
      const rows = await database`
        select b.account_id, e.plan_code
        from billing_customers b
        join entitlements e on e.account_id = b.account_id
        where b.stripe_customer_id = ${customerID}
          and e.plan_code = 'lifetime_byok'
        limit 1
      `;
      if (rows[0]?.account_id) {
        projection = {
          accountID: String(rows[0].account_id),
          plan: "lifetime_byok",
          status: "canceled",
          stripeCustomerID: customerID,
          stripeSubscriptionID: null,
          subscriptionInterval: null,
          subscriptionUnitAmount: null,
          currency: charge.currency,
          currentPeriodEnd: null,
          trialEnd: null,
          trialDeviceID: null,
          eventCreatedAt: new Date(event.created * 1_000)
        };
      }
    }
  }
  if (!projection) {
    await markBillingEvent(database, event.id, transactionRecorded ? "processed" : "ignored", null);
    return transactionRecorded;
  }
  try {
    const rows = await database`
    with customer_projection as (
      insert into billing_customers (
        account_id, stripe_customer_id, stripe_subscription_id,
        subscription_interval, subscription_unit_amount, currency, updated_at
      )
      values (${projection.accountID}::uuid, ${projection.stripeCustomerID},
              ${projection.stripeSubscriptionID}, ${projection.subscriptionInterval},
              ${projection.subscriptionUnitAmount}, ${projection.currency}, now())
      on conflict (account_id) do update
      set stripe_customer_id = coalesce(excluded.stripe_customer_id, billing_customers.stripe_customer_id),
          stripe_subscription_id = coalesce(excluded.stripe_subscription_id, billing_customers.stripe_subscription_id),
          subscription_interval = coalesce(excluded.subscription_interval, billing_customers.subscription_interval),
          subscription_unit_amount = coalesce(excluded.subscription_unit_amount, billing_customers.subscription_unit_amount),
          currency = coalesce(excluded.currency, billing_customers.currency),
          updated_at = now()
      returning account_id
    ), trial_projection as (
      insert into account_trials (account_id, device_id, started_at, ends_at)
      select ${projection.accountID}::uuid,
             ${projection.trialDeviceID}::uuid,
             ${projection.eventCreatedAt.toISOString()}::timestamptz,
             ${projection.trialEnd?.toISOString() ?? null}::timestamptz
      where ${projection.plan}::text = 'pro_byok'
        and ${projection.trialEnd?.toISOString() ?? null}::timestamptz is not null
        and ${projection.stripeSubscriptionID}::text is not null
      on conflict (account_id) do nothing
      returning account_id
    )
    insert into entitlements (
      account_id, plan_code, status, source, trial_end, current_period_end,
      provider_event_created_at, updated_at
    )
    select account_id, ${projection.plan}, ${projection.status}, 'stripe',
           ${projection.trialEnd?.toISOString() ?? null}::timestamptz,
           ${projection.currentPeriodEnd?.toISOString() ?? null}::timestamptz,
           ${projection.eventCreatedAt.toISOString()}::timestamptz, now()
    from customer_projection
    on conflict (account_id) do update
    set plan_code = excluded.plan_code,
        status = excluded.status,
        source = 'stripe',
        trial_end = excluded.trial_end,
        current_period_end = excluded.current_period_end,
        provider_event_created_at = excluded.provider_event_created_at,
        updated_at = now()
    where entitlements.provider_event_created_at is null
       or excluded.provider_event_created_at >= entitlements.provider_event_created_at
    returning account_id
  `;
    await markBillingEvent(database, event.id, "processed", null);
    return Boolean(rows[0]);
  } catch (error) {
    await markBillingEvent(
      database,
      event.id,
      "failed",
      error instanceof Error ? error.name.slice(0, 100) : "unknown"
    );
    throw error;
  }
}

async function persistBillingTransaction(database: Database, event: Stripe.Event): Promise<boolean> {
  let customerID: string | null = null;
  let objectID: string | null = null;
  let transactionType: "invoice" | "refund" | "dispute" | "lifetime_payment" | null = null;
  let amount = 0;
  let currency = "eur";
  let status = "unknown";

  if (event.type === "invoice.paid" || event.type === "invoice.payment_failed") {
    const invoice = event.data.object;
    customerID = stripeID(invoice.customer);
    objectID = invoice.id;
    transactionType = "invoice";
    amount = event.type === "invoice.paid" ? invoice.amount_paid : invoice.amount_due;
    currency = invoice.currency;
    status = event.type === "invoice.paid" ? "paid" : "payment_failed";
  } else if (event.type === "charge.refunded") {
    const charge = event.data.object;
    customerID = stripeID(charge.customer);
    objectID = charge.id;
    transactionType = "refund";
    amount = charge.amount_refunded;
    currency = charge.currency;
    status = charge.amount_refunded >= charge.amount ? "total" : "partial";
  } else if (event.type === "charge.succeeded") {
    const charge = event.data.object;
    if (charge.metadata.plan_code !== "lifetime_byok") return false;
    customerID = stripeID(charge.customer);
    objectID = charge.id;
    transactionType = "lifetime_payment";
    amount = charge.amount;
    currency = charge.currency;
    status = "paid";
  } else if (event.type === "charge.dispute.created" || event.type === "charge.dispute.closed") {
    const dispute = event.data.object;
    const expandedCharge = typeof dispute.charge === "object" ? dispute.charge : null;
    customerID = expandedCharge && !("deleted" in expandedCharge)
      ? stripeID(expandedCharge.customer)
      : null;
    objectID = dispute.id;
    transactionType = "dispute";
    amount = dispute.amount;
    currency = dispute.currency;
    status = dispute.status;
  } else {
    return false;
  }
  const rows = await database`
    insert into billing_transactions (
      account_id, provider, provider_object_id, provider_event_id,
      transaction_type, amount, currency, status, occurred_at
    )
    select b.account_id, 'stripe', ${objectID}, ${event.id}, ${transactionType},
           ${amount}, ${currency}, ${status},
           ${new Date(event.created * 1_000).toISOString()}::timestamptz
    from (values (1)) seed(value)
    left join billing_customers b on b.stripe_customer_id = ${customerID}
    on conflict (provider, provider_object_id, transaction_type) do update
    set provider_event_id = excluded.provider_event_id,
        amount = excluded.amount,
        status = excluded.status,
        occurred_at = excluded.occurred_at,
        recorded_at = now()
    returning id
  `;
  return Boolean(rows[0]);
}

export async function reconcileStripeSubscriptions(
  database: Database,
  stripe: Stripe,
  accountID?: string
): Promise<{ scanned: number; reconciled: number; failures: Array<{ subscriptionID: string; errorCode: string }> }> {
  let cursor = "";
  let scanned = 0;
  let reconciled = 0;
  const failures: Array<{ subscriptionID: string; errorCode: string }> = [];
  while (true) {
    const rows = await database`
      select account_id, stripe_subscription_id
      from billing_customers
      where stripe_subscription_id is not null
        and (${accountID ?? ""} = '' or account_id = nullif(${accountID ?? ""}, '')::uuid)
        and (${cursor} = '' or account_id > nullif(${cursor}, '')::uuid)
      order by account_id asc
      limit 100
    `;
    if (rows.length === 0) break;
    for (const row of rows) {
      cursor = String(row.account_id);
      const subscriptionID = String(row.stripe_subscription_id);
      scanned += 1;
      try {
        const subscription = await stripe.subscriptions.retrieve(subscriptionID);
        const periodEnd = subscription.items.data
          .map((item) => item.current_period_end)
          .sort((left, right) => right - left)[0] ?? 0;
        const now = Math.floor(Date.now() / 1_000);
        const event = {
          id: `reconcile:${subscription.id}:${subscription.status}:${periodEnd}`,
          created: now,
          type: "customer.subscription.updated",
          data: { object: subscription }
        } as unknown as Stripe.Event;
        if (await persistStripeEvent(database, event, JSON.stringify({
          id: subscription.id, status: subscription.status, current_period_end: periodEnd
        }))) reconciled += 1;
      } catch (error) {
        failures.push({
          subscriptionID,
          errorCode: error instanceof Error ? error.name.slice(0, 100) : "unknown"
        });
      }
    }
    if (rows.length < 100 || accountID) break;
  }
  return { scanned, reconciled, failures };
}

async function markBillingEvent(
  database: Database,
  eventID: string,
  status: "processed" | "failed" | "ignored",
  errorCode: string | null
): Promise<void> {
  await database`
    update billing_events
    set status = ${status}, last_error_code = ${errorCode}, processed_at = now()
    where provider = 'stripe' and provider_event_id = ${eventID}
  `;
}

function parsePlan(value: string | undefined): PurchasablePlan | null {
  return purchasablePlans.includes(value as PurchasablePlan)
    ? (value as PurchasablePlan)
    : null;
}

function stripeID(
  value: string | { id: string } | Stripe.DeletedCustomer | null
): string | null {
  if (!value) return null;
  return typeof value === "string" ? value : value.id;
}

function subscriptionStatus(
  status: Stripe.Subscription.Status
): StripeEventProjection["status"] {
  switch (status) {
    case "trialing": return "trialing";
    case "past_due":
    case "unpaid": return "past_due";
    case "canceled":
    case "paused": return "canceled";
    default: return "active";
  }
}
