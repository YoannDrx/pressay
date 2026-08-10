import type Stripe from "stripe";
import { describe, expect, it } from "vitest";
import {
  checkoutSessionParameters,
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
    expect(readConfig({
      ...environment,
      STRIPE_SECRET_KEY: "rk_live_pressay_restricted"
    }).STRIPE_SECRET_KEY).toBe("rk_live_pressay_restricted");
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
      interval: "monthly",
      idempotencyKey: "0de8fbbf-b04a-4779-89ea-3b9964839e99"
    })).toThrow();
    expect(() => checkoutInputSchema.parse({
      plan: "pro_byok",
      interval: "lifetime",
      idempotencyKey: "0de8fbbf-b04a-4779-89ea-3b9964839e99"
    })).toThrow();
  });

  it("creates a no-card trial that cancels if no payment method is added", () => {
    const parameters = checkoutSessionParameters({
      customerID: "cus_pressay",
      priceID: "price_byok_year",
      metadata: {
        account_id: "9e944211-0ccf-48c2-8bca-f10f66bd428b",
        plan_code: "pro_byok"
      },
      interval: "annual",
      trialEligible: true,
      successURL: "https://press-say.app/checkout/success",
      cancelURL: "https://press-say.app/checkout/cancel"
    });

    expect(parameters).toMatchObject({
      mode: "subscription",
      automatic_tax: { enabled: true },
      billing_address_collection: "auto",
      tax_id_collection: { enabled: true },
      allow_promotion_codes: true,
      consent_collection: { terms_of_service: "required" },
      branding_settings: {
        display_name: "Pressay",
        background_color: "#111015",
        button_color: "#5B6CFF",
        border_style: "rounded",
        font_family: "inter"
      },
      payment_method_collection: "if_required",
      subscription_data: {
        trial_period_days: 14,
        trial_settings: {
          end_behavior: { missing_payment_method: "cancel" }
        }
      }
    });
  });

  it("enables tax and promotion codes for the one-time Lifetime offer", () => {
    const parameters = checkoutSessionParameters({
      customerID: "cus_pressay",
      priceID: "price_lifetime",
      metadata: {
        account_id: "9e944211-0ccf-48c2-8bca-f10f66bd428b",
        plan_code: "lifetime_byok"
      },
      interval: "lifetime",
      trialEligible: false,
      successURL: "https://press-say.app/checkout/success",
      cancelURL: "https://press-say.app/checkout/cancel"
    });

    expect(parameters).toMatchObject({
      mode: "payment",
      automatic_tax: { enabled: true },
      allow_promotion_codes: true,
      branding_settings: { display_name: "Pressay" },
      payment_intent_data: {
        metadata: { plan_code: "lifetime_byok" }
      }
    });
  });

  it("derives a paid Lifetime entitlement only from signed Stripe metadata", () => {
    const event = {
      id: "evt_pressay",
      created: 1_780_000_000,
      type: "checkout.session.completed",
      data: {
        object: {
          metadata: {
            account_id: "9e944211-0ccf-48c2-8bca-f10f66bd428b",
            plan_code: "lifetime_byok"
          },
          payment_status: "paid",
          customer: "cus_pressay",
          subscription: null
        }
      }
    } as unknown as Stripe.Event;

    expect(eventProjection(event)).toEqual({
      accountID: "9e944211-0ccf-48c2-8bca-f10f66bd428b",
      plan: "lifetime_byok",
      status: "active",
      stripeCustomerID: "cus_pressay",
      stripeSubscriptionID: null,
      subscriptionInterval: null,
      subscriptionUnitAmount: null,
      currency: null,
      currentPeriodEnd: null,
      trialEnd: null,
      trialDeviceID: null,
      eventCreatedAt: new Date(1_780_000_000_000)
    });
  });

  it("does not grant Lifetime before an asynchronous payment succeeds", () => {
    const event = {
      id: "evt_unpaid_lifetime",
      created: 1_780_000_000,
      type: "checkout.session.completed",
      data: {
        object: {
          metadata: {
            account_id: "9e944211-0ccf-48c2-8bca-f10f66bd428b",
            plan_code: "lifetime_byok"
          },
          payment_status: "unpaid",
          customer: "cus_pressay",
          subscription: null
        }
      }
    } as unknown as Stripe.Event;

    expect(eventProjection(event)).toBeNull();
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
          customer: "cus_pressay",
          amount: 14900,
          amount_refunded: 14900
        }
      }
    } as unknown as Stripe.Event;

    expect(eventProjection(event)).toMatchObject({
      plan: "lifetime_byok",
      status: "canceled",
      eventCreatedAt: new Date(1_780_000_100_000)
    });
  });

  it("keeps Lifetime active after a partial refund", () => {
    const event = {
      id: "evt_partial_refund",
      created: 1_780_000_101,
      type: "charge.refunded",
      data: {
        object: {
          metadata: {
            account_id: "9e944211-0ccf-48c2-8bca-f10f66bd428b",
            plan_code: "lifetime_byok"
          },
          customer: "cus_pressay",
          amount: 14900,
          amount_refunded: 2000
        }
      }
    } as unknown as Stripe.Event;

    expect(eventProjection(event)).toBeNull();
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
          current_period_end: 1_781_300_000,
          items: { data: [] }
        }
      }
    } as unknown as Stripe.Event;

    expect(eventProjection(event)).toMatchObject({
      status: "trialing",
      trialEnd: new Date(1_781_209_800_000),
      currentPeriodEnd: new Date(1_781_300_000_000),
      trialDeviceID: "0de8fbbf-b04a-4779-89ea-3b9964839e99"
    });
  });

  it.each([
    ["customer.subscription.paused", "paused", "canceled"],
    ["customer.subscription.resumed", "active", "active"]
  ] as const)("projects %s into the effective entitlement", (eventType, stripeStatus, expectedStatus) => {
    const event = {
      id: `evt_${stripeStatus}`,
      created: 1_780_000_300,
      type: eventType,
      data: {
        object: {
          id: "sub_pressay",
          status: stripeStatus,
          trial_end: null,
          metadata: {
            account_id: "9e944211-0ccf-48c2-8bca-f10f66bd428b",
            plan_code: "pro_byok"
          },
          customer: "cus_pressay",
          items: { data: [] }
        }
      }
    } as unknown as Stripe.Event;

    expect(eventProjection(event)).toMatchObject({
      status: expectedStatus,
      stripeSubscriptionID: "sub_pressay"
    });
  });
});
