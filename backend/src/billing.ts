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
  };
  interval: BillingInterval;
  trialEligible: boolean;
  successURL: string;
  cancelURL: string;
};

export const checkoutInputSchema = z.object({
  plan: z.enum(purchasablePlans),
  interval: z.enum(["monthly", "annual", "lifetime"]),
  deviceID: z.string().uuid().optional()
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
      currentPeriodEnd: null,
      trialEnd: null,
      trialDeviceID: session.metadata?.device_id ?? null,
      eventCreatedAt: new Date(event.created * 1_000)
    };
  }

  if (
    event.type === "customer.subscription.created" ||
    event.type === "customer.subscription.updated" ||
    event.type === "customer.subscription.deleted"
  ) {
    const subscription = event.data.object;
    const accountID = subscription.metadata.account_id;
    const plan = parsePlan(subscription.metadata.plan_code);
    if (!accountID || !plan) return null;
    const periodEnd = subscription.items.data
      .map((item) => item.current_period_end)
      .filter((value): value is number => typeof value === "number")
      .sort((left, right) => right - left)[0];
    return {
      accountID,
      plan,
      status: event.type === "customer.subscription.deleted"
        ? "canceled"
        : subscriptionStatus(subscription.status),
      stripeCustomerID: stripeID(subscription.customer),
      stripeSubscriptionID: subscription.id,
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
    const accountID = charge.metadata.account_id;
    const plan = parsePlan(charge.metadata.plan_code);
    if (!accountID || !plan) return null;
    return {
      accountID,
      plan,
      status: "canceled",
      stripeCustomerID: stripeID(charge.customer),
      stripeSubscriptionID: null,
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
  let projection = eventProjection(event);
  if (!projection && event.type === "charge.refunded") {
    const customerID = stripeID(event.data.object.customer);
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
          currentPeriodEnd: null,
          trialEnd: null,
          trialDeviceID: null,
          eventCreatedAt: new Date(event.created * 1_000)
        };
      }
    }
  }
  if (!projection) return false;
  const payloadHash = createHash("sha256").update(rawBody).digest("hex");
  const rows = await database`
    with inserted_event as (
      insert into billing_events (
        provider, provider_event_id, event_type, payload_sha256
      ) values ('stripe', ${event.id}, ${event.type}, ${payloadHash})
      on conflict (provider, provider_event_id) do nothing
      returning 1
    ), customer_projection as (
      insert into billing_customers (
        account_id, stripe_customer_id, stripe_subscription_id, updated_at
      )
      select ${projection.accountID}::uuid, ${projection.stripeCustomerID},
             ${projection.stripeSubscriptionID}, now()
      from inserted_event
      on conflict (account_id) do update
      set stripe_customer_id = coalesce(excluded.stripe_customer_id, billing_customers.stripe_customer_id),
          stripe_subscription_id = coalesce(excluded.stripe_subscription_id, billing_customers.stripe_subscription_id),
          updated_at = now()
      returning account_id
    ), trial_projection as (
      insert into account_trials (account_id, device_id, started_at, ends_at)
      select ${projection.accountID}::uuid,
             ${projection.trialDeviceID}::uuid,
             ${projection.eventCreatedAt.toISOString()}::timestamptz,
             ${projection.trialEnd?.toISOString() ?? null}::timestamptz
      from inserted_event
      where ${projection.plan} = 'pro_byok'
        and ${projection.trialEnd?.toISOString() ?? null}::timestamptz is not null
        and ${projection.stripeSubscriptionID} is not null
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
  return Boolean(rows[0]);
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
