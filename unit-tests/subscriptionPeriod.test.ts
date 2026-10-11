import { describe, expect, test } from "bun:test";
import english from "../src/i18n/locales/en/translation.json";
import french from "../src/i18n/locales/fr/translation.json";
import { priceWithPeriod } from "../src/lib/subscriptionPeriod";

function translator(catalogue: unknown) {
  return (key: string, options: Record<string, unknown> = {}) => {
    const template = key
      .split(".")
      .reduce<unknown>(
        (node, part) =>
          node && typeof node === "object"
            ? (node as Record<string, unknown>)[part]
            : undefined,
        catalogue,
      );
    if (typeof template !== "string") throw new Error(`missing ${key}`);
    return template.replace(/\{\{(\w+)\}\}/g, (_, name: string) =>
      String(options[name]),
    );
  };
}

describe("subscription price with period", () => {
  test("monthly and annual plans show their billing period", () => {
    const t = translator(english);
    expect(
      priceWithPeriod(t, {
        displayPrice: "€7.99",
        subscriptionPeriodUnit: "month",
        subscriptionPeriodValue: 1,
      }),
    ).toBe("€7.99 / month");
    expect(
      priceWithPeriod(t, {
        displayPrice: "€79.99",
        subscriptionPeriodUnit: "year",
        subscriptionPeriodValue: 1,
      }),
    ).toBe("€79.99 / year");
    expect(
      priceWithPeriod(t, {
        displayPrice: "€19.99",
        subscriptionPeriodUnit: "month",
        subscriptionPeriodValue: 3,
      }),
    ).toBe("€19.99 every 3 months");
  });

  test("every period unit is translated in English and French", () => {
    for (const catalogue of [english, french]) {
      const t = translator(catalogue);
      for (const unit of ["day", "week", "month", "year"] as const) {
        for (const value of [1, 2]) {
          expect(
            priceWithPeriod(t, {
              displayPrice: "1",
              subscriptionPeriodUnit: unit,
              subscriptionPeriodValue: value,
            }),
          ).toContain("1");
        }
      }
    }
  });

  test("an unknown period falls back to the bare price", () => {
    const t = translator(english);
    expect(
      priceWithPeriod(t, {
        displayPrice: "€7.99",
        subscriptionPeriodUnit: null,
        subscriptionPeriodValue: null,
      }),
    ).toBe("€7.99");
  });
});
