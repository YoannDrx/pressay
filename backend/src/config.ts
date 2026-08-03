import { z } from "zod";

const schema = z.object({
  DATABASE_URL: z.string().url().startsWith("postgresql://"),
  PRESSAY_JWT_ISSUER: z.string().url(),
  PRESSAY_JWT_AUDIENCE: z.string().min(1),
  PRESSAY_JWT_JWKS_URL: z.string().url(),
  CLERK_SECRET_KEY: z.string().startsWith("sk_").optional(),
  CRON_SECRET: z.string().min(32).optional(),
  STRIPE_SECRET_KEY: z.string().startsWith("sk_").optional(),
  STRIPE_WEBHOOK_SECRET: z.string().startsWith("whsec_").optional(),
  STRIPE_PRICE_PRO_BYOK_MONTHLY: z.string().startsWith("price_").optional(),
  STRIPE_PRICE_PRO_BYOK_ANNUAL: z.string().startsWith("price_").optional(),
  STRIPE_PRICE_PRO_CLOUD_MONTHLY: z.string().startsWith("price_").optional(),
  STRIPE_PRICE_PRO_CLOUD_ANNUAL: z.string().startsWith("price_").optional(),
  STRIPE_PRICE_LIFETIME_BYOK: z.string().startsWith("price_").optional(),
  PRESSAY_CHECKOUT_SUCCESS_URL: z.string().url().optional(),
  PRESSAY_CHECKOUT_CANCEL_URL: z.string().url().optional(),
  PRESSAY_BILLING_RETURN_URL: z.string().url().optional(),
  PRESSAY_ENTITLEMENT_SIGNING_PRIVATE_KEY: z.string().min(32).optional(),
  PRESSAY_FOUNDING_CLAIM_DEADLINE: z.coerce.date().optional(),
  PRESSAY_ALLOWED_ORIGINS: z.string().default(
    "https://press-say.app,https://staging.press-say.app"
  ),
  PORT: z.coerce.number().int().positive().default(8787),
  NODE_ENV: z.enum(["development", "test", "production"]).default("development")
}).superRefine((config, context) => {
  if (config.NODE_ENV === "production" && !config.PRESSAY_ENTITLEMENT_SIGNING_PRIVATE_KEY) {
    context.addIssue({
      code: "custom",
      path: ["PRESSAY_ENTITLEMENT_SIGNING_PRIVATE_KEY"],
      message: "an Ed25519 entitlement signing key is required in production"
    });
  }
  if (config.NODE_ENV === "production" && !config.CLERK_SECRET_KEY) {
    context.addIssue({
      code: "custom",
      path: ["CLERK_SECRET_KEY"],
      message: "Clerk server credentials are required for account deletion in production"
    });
  }
  if (config.NODE_ENV === "production" && !config.CRON_SECRET) {
    context.addIssue({
      code: "custom",
      path: ["CRON_SECRET"],
      message: "a cron secret is required for billing reconciliation in production"
    });
  }
});

export type AppConfig = z.infer<typeof schema>;

export function readConfig(environment: NodeJS.ProcessEnv = process.env): AppConfig {
  return schema.parse(environment);
}

export function stripeIsConfigured(config: AppConfig): boolean {
  return Boolean(
    config.STRIPE_SECRET_KEY &&
    config.STRIPE_WEBHOOK_SECRET &&
    config.STRIPE_PRICE_PRO_BYOK_MONTHLY &&
    config.STRIPE_PRICE_PRO_BYOK_ANNUAL &&
    config.STRIPE_PRICE_LIFETIME_BYOK &&
    config.PRESSAY_CHECKOUT_SUCCESS_URL &&
    config.PRESSAY_CHECKOUT_CANCEL_URL &&
    config.PRESSAY_BILLING_RETURN_URL
  );
}
