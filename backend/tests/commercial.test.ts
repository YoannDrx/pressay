import { describe, expect, it } from "vitest";
import type Stripe from "stripe";
import { invoicePaymentReference, invoiceSubscriptionID, referralRestoredTrialEnd } from "../src/commercial.js";

function invoice(fields: Record<string, unknown>): Stripe.Invoice {
  return fields as unknown as Stripe.Invoice;
}

describe("commercial Stripe compatibility", () => {
  it("reads a subscription from the legacy webhook payload", () => {
    expect(invoiceSubscriptionID(invoice({
      id: "in_legacy",
      subscription: "sub_legacy",
      parent: null
    }))).toBe("sub_legacy");
  });

  it("reads a subscription from the current webhook payload", () => {
    expect(invoiceSubscriptionID(invoice({
      id: "in_current",
      parent: { subscription_details: { subscription: { id: "sub_current" } } }
    }))).toBe("sub_current");
  });

  it("reads payment identifiers from the legacy invoice fields", () => {
    expect(invoicePaymentReference(invoice({
      id: "in_legacy",
      payment_intent: "pi_legacy",
      charge: "ch_legacy"
    }))).toEqual({
      invoiceID: "in_legacy",
      paymentIntentID: "pi_legacy",
      chargeID: "ch_legacy"
    });
  });

  it("reads payment identifiers from the current invoice payments list", () => {
    expect(invoicePaymentReference(invoice({
      id: "in_current",
      payments: {
        data: [{
          status: "paid",
          payment: { payment_intent: { id: "pi_current" }, charge: { id: "ch_current" } }
        }]
      }
    }))).toEqual({
      invoiceID: "in_current",
      paymentIntentID: "pi_current",
      chargeID: "ch_current"
    });
  });

  it("restores the original future billing boundary instead of shortening paid access", () => {
    expect(referralRestoredTrialEnd("2026-09-01T00:00:00.000Z", Date.parse("2026-08-12T00:00:00.000Z")))
      .toBe(Date.parse("2026-09-01T00:00:00.000Z") / 1_000);
    expect(referralRestoredTrialEnd("2026-08-01T00:00:00.000Z", Date.parse("2026-08-12T00:00:00.000Z")))
      .toBe("now");
  });
});
