import { serve } from "@hono/node-server";
import app from "./index.js";
import { readConfig } from "./config.js";

const config = readConfig();

serve({ fetch: app.fetch, port: config.PORT }, (info) => {
  console.log(`Pressay API listening on http://localhost:${info.port}`);
});
