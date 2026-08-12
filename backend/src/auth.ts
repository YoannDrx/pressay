import { createRemoteJWKSet, decodeJwt, jwtVerify } from "jose";
import type { MiddlewareHandler } from "hono";
import type { AppConfig } from "./config.js";

export type AuthVariables = {
  authSubject: string;
  authEmail: string | undefined;
  authName: string | undefined;
  authProvider: "clerk" | "better-auth" | "pressay-web";
  authFactorVerificationAge: readonly [number, number] | undefined;
  authReverificationID: string | undefined;
  authStepUpAt: number | undefined;
  authStepUpMethod: string | undefined;
  authSessionID: string | undefined;
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

export function hasRecentStrongAuthentication(
  factorVerificationAge: readonly [number, number] | undefined,
  stepUpAt: number | undefined,
  maximumAgeMinutes: number,
  nowSeconds = Math.floor(Date.now() / 1000)
): boolean {
  if (hasRecentMultiFactorAuthentication(factorVerificationAge, maximumAgeMinutes)) return true;
  if (typeof stepUpAt !== "number" || !Number.isFinite(stepUpAt)) return false;
  const ageSeconds = nowSeconds - stepUpAt;
  return ageSeconds >= -60 && ageSeconds <= maximumAgeMinutes * 60;
}

export function authenticationMiddleware(
  config: Pick<AppConfig,
    | "PRESSAY_JWT_ISSUER"
    | "PRESSAY_JWT_AUDIENCE"
    | "PRESSAY_JWT_JWKS_URL"
    | "PRESSAY_BETTER_AUTH_JWT_ISSUER"
    | "PRESSAY_BETTER_AUTH_JWT_AUDIENCE"
    | "PRESSAY_BETTER_AUTH_JWKS_URL"
    | "PRESSAY_INTERNAL_JWT_ISSUER"
    | "PRESSAY_INTERNAL_JWT_SECRET"
  >
): MiddlewareHandler<{ Variables: AuthVariables }> {
  const clerkKeySet = config.PRESSAY_JWT_JWKS_URL
    ? createRemoteJWKSet(new URL(config.PRESSAY_JWT_JWKS_URL))
    : null;
  const clerkIssuer = config.PRESSAY_JWT_ISSUER;
  const clerkAudiences = (config.PRESSAY_JWT_AUDIENCE ?? "")
    .split(",")
    .map((audience) => audience.trim())
    .filter(Boolean);
  const betterAuthKeySet = config.PRESSAY_BETTER_AUTH_JWKS_URL
    ? createRemoteJWKSet(new URL(config.PRESSAY_BETTER_AUTH_JWKS_URL))
    : null;
  const betterAuthIssuer = config.PRESSAY_BETTER_AUTH_JWT_ISSUER;
  const betterAuthAudiences = config.PRESSAY_BETTER_AUTH_JWT_AUDIENCE
    .split(",")
    .map((audience) => audience.trim())
    .filter(Boolean);
  const internalSecret = config.PRESSAY_INTERNAL_JWT_SECRET
    ? new TextEncoder().encode(config.PRESSAY_INTERNAL_JWT_SECRET)
    : null;

  return async (context, next) => {
    const authorization = context.req.header("Authorization");
    const token = authorization?.startsWith("Bearer ")
      ? authorization.slice("Bearer ".length)
      : undefined;
    if (!token) {
      return context.json({ error: "missing_bearer_token" }, 401);
    }

    try {
      const unverifiedIssuer = decodeJwt(token).iss;
      let provider: AuthVariables["authProvider"];
      let verified;
      if (unverifiedIssuer === config.PRESSAY_INTERNAL_JWT_ISSUER && internalSecret) {
        provider = "pressay-web";
        verified = await jwtVerify(token, internalSecret, {
          algorithms: ["HS256"],
          issuer: config.PRESSAY_INTERNAL_JWT_ISSUER,
          audience: "pressay-api",
          maxTokenAge: "5m"
        });
      } else if (
        unverifiedIssuer === betterAuthIssuer &&
        betterAuthKeySet &&
        betterAuthIssuer
      ) {
        provider = "better-auth";
        verified = await jwtVerify(token, betterAuthKeySet, {
          algorithms: ["EdDSA", "ES256", "ES512", "RS256", "PS256"],
          issuer: betterAuthIssuer,
          audience: betterAuthAudiences
        });
      } else if (unverifiedIssuer === clerkIssuer && clerkKeySet && clerkIssuer) {
        provider = "clerk";
        verified = await jwtVerify(token, clerkKeySet, {
          issuer: clerkIssuer,
          audience: clerkAudiences
        });
      } else {
        return context.json({ error: "untrusted_token_issuer" }, 401);
      }
      const { payload } = verified;
      if (!payload.sub) {
        return context.json({ error: "missing_token_subject" }, 401);
      }
      context.set("authProvider", provider);
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
      context.set(
        "authStepUpAt",
        typeof payload.pressay_step_up_at === "number" ? payload.pressay_step_up_at : undefined
      );
      context.set(
        "authStepUpMethod",
        typeof payload.pressay_step_up_method === "string" ? payload.pressay_step_up_method : undefined
      );
      context.set(
        "authSessionID",
        typeof payload.sid === "string" ? payload.sid : undefined
      );
      await next();
    } catch {
      return context.json({ error: "invalid_token" }, 401);
    }
  };
}
