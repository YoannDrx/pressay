import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const MONTHLY_PRODUCT_ID = "app.pressay.desktop.mas.pro.monthly";
const ANNUAL_PRODUCT_ID = "app.pressay.desktop.mas.pro.annual";

type Localization = {
  locale: string;
  displayName: string;
  description: string;
};

type Subscription = {
  productID: string;
  displayPrice: string;
  recurringSubscriptionPeriod: string;
  groupNumber: number;
  introductoryOffer: unknown;
  localizations: Localization[];
};

type StoreKitConfiguration = {
  version: { major: number };
  products: unknown[];
  nonRenewingSubscriptions: unknown[];
  subscriptionGroups: Array<{
    name: string;
    localizations: Localization[];
    subscriptions: Subscription[];
  }>;
};

function invariant(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(`StoreKit catalogue invalid: ${message}`);
}

function locales(localizations: Localization[]): string[] {
  return localizations.map(({ locale }) => locale).sort();
}

const path = resolve(
  import.meta.dirname,
  "..",
  "src-tauri",
  "StoreKit",
  "Pressay.storekit",
);
const catalogue = JSON.parse(
  readFileSync(path, "utf8"),
) as StoreKitConfiguration;

invariant(catalogue.version.major === 3, "expected StoreKit schema version 3");
invariant(catalogue.products.length === 0, "one-time products are not allowed");
invariant(
  catalogue.nonRenewingSubscriptions.length === 0,
  "non-renewing subscriptions are not allowed",
);
invariant(
  catalogue.subscriptionGroups.length === 1,
  "exactly one Pressay Pro subscription group is required",
);

const [group] = catalogue.subscriptionGroups;
invariant(
  group.name === "Pressay Pro",
  "subscription group name must be Pressay Pro",
);
invariant(
  JSON.stringify(locales(group.localizations)) ===
    JSON.stringify(["en_US", "fr_FR"]),
  "subscription group must have exact FR/EN localizations",
);

const subscriptions = new Map(
  group.subscriptions.map((subscription) => [
    subscription.productID,
    subscription,
  ]),
);
invariant(
  subscriptions.size === 2,
  "exactly two recurring products are required",
);
invariant(
  subscriptions.has(MONTHLY_PRODUCT_ID) && subscriptions.has(ANNUAL_PRODUCT_ID),
  "monthly and annual Pressay Pro product IDs are required",
);

const monthly = subscriptions.get(MONTHLY_PRODUCT_ID)!;
const annual = subscriptions.get(ANNUAL_PRODUCT_ID)!;
invariant(monthly.displayPrice === "7.99", "monthly price must be EUR 7.99");
invariant(annual.displayPrice === "69.00", "annual price must be EUR 69.00");
invariant(
  monthly.recurringSubscriptionPeriod === "P1M",
  "monthly period must be P1M",
);
invariant(
  annual.recurringSubscriptionPeriod === "P1Y",
  "annual period must be P1Y",
);
invariant(
  monthly.groupNumber === annual.groupNumber,
  "equal Pro benefits must share one subscription level",
);
invariant(
  monthly.introductoryOffer === null && annual.introductoryOffer === null,
  "launch products must not include a trial or introductory offer",
);

for (const subscription of [monthly, annual]) {
  invariant(
    JSON.stringify(locales(subscription.localizations)) ===
      JSON.stringify(["en_US", "fr_FR"]),
    `${subscription.productID} must have exact FR/EN localizations`,
  );
  for (const localization of subscription.localizations) {
    invariant(
      localization.displayName.trim().length > 0,
      "display name is required",
    );
    invariant(
      localization.description.trim().length > 0,
      "description is required",
    );
  }
}

console.log(
  `StoreKit catalogue valid: ${MONTHLY_PRODUCT_ID} and ${ANNUAL_PRODUCT_ID} share level ${monthly.groupNumber}.`,
);
