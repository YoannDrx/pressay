import { createRemoteJWKSet, jwtVerify } from "jose";
import type { MiddlewareHandler } from "hono";
import type { AppConfig } from "./config.js";

export type AuthVariables = {
  authSubject: string;
  authEmail: string | undefined;
  authName: string | undefined;
};

export function authenticationMiddleware(
  config: Pick<AppConfig, "PRESSAY_JWT_ISSUER" | "PRESSAY_JWT_AUDIENCE" | "PRESSAY_JWT_JWKS_URL">
): MiddlewareHandler<{ Variables: AuthVariables }> {
  const keySet = createRemoteJWKSet(new URL(config.PRESSAY_JWT_JWKS_URL));

  return async (context, next) => {
    const authorization = context.req.header("Authorization");
    const token = authorization?.startsWith("Bearer ")
      ? authorization.slice("Bearer ".length)
      : undefined;
    if (!token) {
      return context.json({ error: "missing_bearer_token" }, 401);
    }

    try {
      const { payload } = await jwtVerify(token, keySet, {
        issuer: config.PRESSAY_JWT_ISSUER,
        audience: config.PRESSAY_JWT_AUDIENCE
      });
      if (!payload.sub) {
        return context.json({ error: "missing_token_subject" }, 401);
      }
      context.set("authSubject", payload.sub);
      context.set(
        "authEmail",
        payload.email_verified === true && typeof payload.email === "string"
          ? payload.email
          : undefined
      );
      context.set(
        "authName",
        typeof payload.name === "string" ? payload.name : undefined
      );
      await next();
    } catch {
      return context.json({ error: "invalid_token" }, 401);
    }
  };
}
