import type { StoreKitProduct } from "@/bindings";

type Translate = (key: string, options?: Record<string, unknown>) => string;

/**
 * "7,99 € / month": App Review 3.1.2 requires the billing period next to the
 * price of an auto-renewable subscription. Falls back to the bare price when
 * StoreKit did not report a period.
 */
export function priceWithPeriod(
  t: Translate,
  product: Pick<
    StoreKitProduct,
    "displayPrice" | "subscriptionPeriodUnit" | "subscriptionPeriodValue"
  >,
): string {
  const unit = product.subscriptionPeriodUnit;
  if (!unit) return product.displayPrice;
  const count = product.subscriptionPeriodValue ?? 1;
  const key =
    count === 1
      ? `cloud.appStore.period.${unit}`
      : `cloud.appStore.period.${unit}Multiple`;
  return t(key, { price: product.displayPrice, count });
}
