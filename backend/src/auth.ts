import { createRemoteJWKSet, jwtVerify } from "jose";
import type { MiddlewareHandler } from "hono";
import type { AppConfig } from "./config.js";

export type AuthVariables = {
  authSubject: string;
  authEmail: string | undefined;
  authName: string | undefined;
  authFactorVerificationAge: readonly [number, number] | undefined;
  authReverificationID: string | undefined;
};

export function hasRecentMultiFactorAuthentication(
  factorVerificationAge: readonly [number, number] | undefined,
  maximumAgeMinutes: number
): boolean {
  return Boolean(
    factorVerificationAge &&
    factorVerificationAge[0] >= 0 &&
    factorVerificationAge[1] >= 0 &&
    factorVerificationAge[0] <= maximumAgeMinutes &&
    factorVerificationAge[1] <= maximumAgeMinutes
  );
}

export function authenticationMiddleware(
  config: Pick<AppConfig, "PRESSAY_JWT_ISSUER" | "PRESSAY_JWT_AUDIENCE" | "PRESSAY_JWT_JWKS_URL">
): MiddlewareHandler<{ Variables: AuthVariables }> {
  const keySet = createRemoteJWKSet(new URL(config.PRESSAY_JWT_JWKS_URL));
  const acceptedAudiences = config.PRESSAY_JWT_AUDIENCE
    .split(",")
    .map((audience) => audience.trim())
    .filter(Boolean);

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
        audience: acceptedAudiences
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
      const factorVerificationAge = payload.fva;
      context.set(
        "authFactorVerificationAge",
        Array.isArray(factorVerificationAge) &&
        factorVerificationAge.length === 2 &&
        factorVerificationAge.every((age) => typeof age === "number")
          ? factorVerificationAge as [number, number]
          : undefined
      );
      context.set(
        "authReverificationID",
        typeof payload.reverification_id === "string"
          ? payload.reverification_id
          : undefined
      );
      await next();
    } catch {
      return context.json({ error: "invalid_token" }, 401);
    }
  };
}
