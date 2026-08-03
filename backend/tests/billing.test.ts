import type Stripe from "stripe";
import { describe, expect, it } from "vitest";
import {
  checkoutInputSchema,
  eventProjection,
  priceID
} from "../src/billing.js";
import { readConfig, stripeIsConfigured } from "../src/config.js";

const environment = {
  DATABASE_URL: "postgresql://example.test/pressay",
  PRESSAY_JWT_ISSUER: "https://identity.example.test",
  PRESSAY_JWT_AUDIENCE: "pressay-api",
  PRESSAY_JWT_JWKS_URL: "https://identity.example.test/jwks.json",
  STRIPE_SECRET_KEY: "sk_test_pressay",
  STRIPE_WEBHOOK_SECRET: "whsec_pressay",
  STRIPE_PRICE_PRO_BYOK_MONTHLY: "price_byok_month",
  STRIPE_PRICE_PRO_BYOK_ANNUAL: "price_byok_year",
  STRIPE_PRICE_PRO_CLOUD_MONTHLY: "price_cloud_month",
  STRIPE_PRICE_PRO_CLOUD_ANNUAL: "price_cloud_year",
  STRIPE_PRICE_LIFETIME_BYOK: "price_lifetime",
  PRESSAY_CHECKOUT_SUCCESS_URL: "https://pressay.app/success",
  PRESSAY_CHECKOUT_CANCEL_URL: "https://pressay.app/cancel",
  PRESSAY_BILLING_RETURN_URL: "https://pressay.app/account"
};

describe("Stripe billing", () => {
  it("only enables Stripe when the complete configuration is available", () => {
    expect(stripeIsConfigured(readConfig(environment))).toBe(true);
    const {
      STRIPE_PRICE_PRO_CLOUD_MONTHLY: _cloudMonthly,
      STRIPE_PRICE_PRO_CLOUD_ANNUAL: _cloudAnnual,
      ...byokOnly
    } = environment;
    expect(stripeIsConfigured(readConfig(byokOnly))).toBe(true);
    const { STRIPE_WEBHOOK_SECRET: _, ...incomplete } = environment;
    expect(stripeIsConfigured(readConfig(incomplete))).toBe(false);
  });

  it("maps a server-side plan and interval to an allowlisted Price ID", () => {
    const config = readConfig(environment);
    expect(priceID(config, "pro_byok", "monthly")).toBe("price_byok_month");
    expect(priceID(config, "lifetime_byok", "lifetime")).toBe("price_lifetime");
    expect(priceID(config, "pro_byok", "lifetime")).toBeUndefined();
  });

  it("rejects incoherent lifetime checkout combinations", () => {
    expect(() => checkoutInputSchema.parse({
      plan: "lifetime_byok",
      interval: "monthly"
    })).toThrow();
    expect(() => checkoutInputSchema.parse({
      plan: "pro_byok",
      interval: "lifetime"
    })).toThrow();
  });

  it("derives entitlements only from signed Stripe event metadata", () => {
    const event = {
      id: "evt_pressay",
      created: 1_780_000_000,
      type: "checkout.session.completed",
      data: {
        object: {
          metadata: {
            account_id: "9e944211-0ccf-48c2-8bca-f10f66bd428b",
            plan_code: "pro_byok"
          },
          customer: "cus_pressay",
          subscription: "sub_pressay"
        }
      }
    } as unknown as Stripe.Event;

    expect(eventProjection(event)).toEqual({
      accountID: "9e944211-0ccf-48c2-8bca-f10f66bd428b",
      plan: "pro_byok",
      status: "active",
      stripeCustomerID: "cus_pressay",
      stripeSubscriptionID: "sub_pressay",
      currentPeriodEnd: null,
      trialEnd: null,
      trialDeviceID: null,
      eventCreatedAt: new Date(1_780_000_000_000)
    });
  });

  it("revokes a lifetime entitlement after a signed refund event", () => {
    const event = {
      id: "evt_refund",
      created: 1_780_000_100,
      type: "charge.refunded",
      data: {
        object: {
          metadata: {
            account_id: "9e944211-0ccf-48c2-8bca-f10f66bd428b",
            plan_code: "lifetime_byok"
          },
          customer: "cus_pressay"
        }
      }
    } as unknown as Stripe.Event;

    expect(eventProjection(event)).toMatchObject({
      plan: "lifetime_byok",
      status: "canceled",
      eventCreatedAt: new Date(1_780_000_100_000)
    });
  });

  it("projects Stripe trial and device metadata for account-level anti-abuse", () => {
    const event = {
      id: "evt_trial",
      created: 1_780_000_200,
      type: "customer.subscription.updated",
      data: {
        object: {
          id: "sub_trial",
          status: "trialing",
          trial_end: 1_781_209_800,
          metadata: {
            account_id: "9e944211-0ccf-48c2-8bca-f10f66bd428b",
            plan_code: "pro_byok",
            device_id: "0de8fbbf-b04a-4779-89ea-3b9964839e99"
          },
          customer: "cus_pressay",
          items: { data: [] }
        }
      }
    } as unknown as Stripe.Event;

    expect(eventProjection(event)).toMatchObject({
      status: "trialing",
      trialEnd: new Date(1_781_209_800_000),
      trialDeviceID: "0de8fbbf-b04a-4779-89ea-3b9964839e99"
    });
  });
});
