import { createApp } from "./application.js";
import { createStripeClient } from "./billing.js";
import { readConfig, stripeIsConfigured } from "./config.js";
import { createDatabase } from "./db.js";

const config = readConfig();
const stripe = stripeIsConfigured(config) && config.STRIPE_SECRET_KEY
  ? createStripeClient(config.STRIPE_SECRET_KEY)
  : null;
const app = createApp(config, createDatabase(config.DATABASE_URL), stripe);

export default app;
