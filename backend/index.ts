import { Hono } from "hono";
import { createApp } from "./src/application.js";
import { createStripeClient } from "./src/billing.js";
import { readConfig, stripeIsConfigured } from "./src/config.js";
import { createDatabase } from "./src/db.js";

const config = readConfig();
const stripe = stripeIsConfigured(config) && config.STRIPE_SECRET_KEY
  ? createStripeClient(config.STRIPE_SECRET_KEY)
  : null;
// Vercel's Hono preset detects a direct framework import in the entrypoint.
void Hono;

const app = createApp(
  config,
  createDatabase(config.DATABASE_URL),
  stripe
);

export default app;
