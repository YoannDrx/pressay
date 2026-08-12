begin;

-- Better Auth lives beside the commercial schema during the Clerk transition.
-- Text IDs deliberately allow importing existing Clerk user IDs unchanged so
-- accounts.auth_subject, billing, grants, referrals and RBAC keep their links.
create table auth_users (
  id text primary key,
  name text not null,
  email text not null unique,
  "emailVerified" boolean not null,
  image text,
  "createdAt" timestamptz not null default current_timestamp,
  "updatedAt" timestamptz not null default current_timestamp,
  "twoFactorEnabled" boolean
);

create table auth_sessions (
  id text primary key,
  "expiresAt" timestamptz not null,
  token text not null unique,
  "createdAt" timestamptz not null default current_timestamp,
  "updatedAt" timestamptz not null,
  "ipAddress" text,
  "userAgent" text,
  "userId" text not null references auth_users(id) on delete cascade
);

create table auth_accounts (
  id text primary key,
  issuer text not null,
  "accountId" text not null,
  "providerId" text not null,
  "userId" text not null references auth_users(id) on delete cascade,
  "accessToken" text,
  "refreshToken" text,
  "idToken" text,
  "accessTokenExpiresAt" timestamptz,
  "refreshTokenExpiresAt" timestamptz,
  scope text,
  password text,
  "createdAt" timestamptz not null default current_timestamp,
  "updatedAt" timestamptz not null
);

create table auth_verifications (
  id text primary key,
  identifier text not null,
  value text not null,
  "expiresAt" timestamptz not null,
  "createdAt" timestamptz not null default current_timestamp,
  "updatedAt" timestamptz not null default current_timestamp
);

create table auth_two_factors (
  id text primary key,
  secret text not null,
  "backupCodes" text not null,
  "userId" text not null references auth_users(id) on delete cascade,
  verified boolean,
  "failedVerificationCount" integer,
  "lockedUntil" timestamptz
);

create table auth_passkeys (
  id text primary key,
  name text,
  "publicKey" text not null,
  "userId" text not null references auth_users(id) on delete cascade,
  "credentialID" text not null,
  counter integer not null,
  "deviceType" text not null,
  "backedUp" boolean not null,
  transports text,
  "createdAt" timestamptz,
  aaguid text
);

create table auth_jwks (
  id text primary key,
  "publicKey" text not null,
  "privateKey" text not null,
  "createdAt" timestamptz not null,
  "expiresAt" timestamptz,
  alg text,
  crv text
);

create table auth_oauth_clients (
  id text primary key,
  "clientId" text not null unique,
  "clientSecret" text,
  "clientDiscoveryId" text,
  disabled boolean,
  "skipConsent" boolean,
  "enableEndSession" boolean,
  "subjectType" text,
  scopes jsonb,
  "clientCredentialsScopes" jsonb,
  "userId" text references auth_users(id) on delete cascade,
  "createdAt" timestamptz,
  "updatedAt" timestamptz,
  name text,
  uri text,
  icon text,
  contacts jsonb,
  tos text,
  policy text,
  "softwareId" text,
  "softwareVersion" text,
  "softwareStatement" text,
  "redirectUris" jsonb not null,
  "postLogoutRedirectUris" jsonb,
  "backchannelLogoutUri" text,
  "backchannelLogoutSessionRequired" boolean,
  "tokenEndpointAuthMethod" text,
  "applicationType" text,
  jwks text,
  "jwksUri" text,
  "grantTypes" jsonb,
  "responseTypes" jsonb,
  "requirePKCE" boolean,
  "dpopBoundAccessTokens" boolean,
  "referenceId" text,
  metadata jsonb
);

create table auth_oauth_resources (
  id text primary key,
  identifier text not null unique,
  name text not null,
  "accessTokenTtl" integer,
  "refreshTokenTtl" integer,
  "signingAlgorithm" text,
  "signingKeyId" text,
  "allowedScopes" jsonb,
  "customClaims" jsonb,
  "dpopBoundAccessTokensRequired" boolean,
  disabled boolean,
  "createdAt" timestamptz,
  "updatedAt" timestamptz,
  "policyVersion" integer,
  metadata jsonb
);

create table auth_oauth_client_resources (
  id text primary key,
  "clientId" text not null references auth_oauth_clients("clientId") on delete cascade,
  "resourceId" text not null references auth_oauth_resources(identifier) on delete cascade,
  metadata jsonb,
  "createdAt" timestamptz,
  unique ("clientId", "resourceId")
);

create table auth_oauth_refresh_tokens (
  id text primary key,
  token text not null unique,
  "clientId" text not null references auth_oauth_clients("clientId") on delete cascade,
  "sessionId" text references auth_sessions(id) on delete set null,
  "userId" text not null references auth_users(id) on delete cascade,
  "referenceId" text,
  "authorizationCodeId" text,
  resources jsonb,
  "requestedUserInfoClaims" jsonb,
  "expiresAt" timestamptz not null,
  "createdAt" timestamptz not null,
  revoked timestamptz,
  "rotatedAt" timestamptz,
  "rotationReplayResponse" text,
  "rotationReplayExpiresAt" timestamptz,
  "authTime" timestamptz,
  confirmation jsonb,
  scopes jsonb not null
);

create table auth_oauth_access_tokens (
  id text primary key,
  token text not null unique,
  "clientId" text not null references auth_oauth_clients("clientId") on delete cascade,
  "sessionId" text references auth_sessions(id) on delete set null,
  "userId" text references auth_users(id) on delete cascade,
  "referenceId" text,
  "authorizationCodeId" text,
  resources jsonb,
  "requestedUserInfoClaims" jsonb,
  "refreshId" text references auth_oauth_refresh_tokens(id) on delete cascade,
  "expiresAt" timestamptz not null,
  "createdAt" timestamptz not null,
  revoked timestamptz,
  confirmation jsonb,
  scopes jsonb not null
);

create table auth_oauth_consents (
  id text primary key,
  "clientId" text not null references auth_oauth_clients("clientId") on delete cascade,
  "userId" text references auth_users(id) on delete cascade,
  "referenceId" text,
  resources jsonb,
  "requestedUserInfoClaims" jsonb,
  scopes jsonb not null,
  "createdAt" timestamptz not null,
  "updatedAt" timestamptz not null
);

create table auth_oauth_client_assertions (
  id text primary key,
  "expiresAt" timestamptz not null
);

create table auth_rate_limits (
  id text primary key,
  key text not null unique,
  count integer not null,
  "lastRequest" bigint not null
);

create index auth_sessions_user_id_idx on auth_sessions ("userId");
create index auth_accounts_user_id_idx on auth_accounts ("userId");
create index auth_verifications_identifier_idx on auth_verifications (identifier);
create index auth_two_factors_secret_idx on auth_two_factors (secret);
create index auth_two_factors_user_id_idx on auth_two_factors ("userId");
create index auth_passkeys_user_id_idx on auth_passkeys ("userId");
create unique index auth_passkeys_credential_id_idx on auth_passkeys ("credentialID");
create index auth_oauth_clients_user_id_idx on auth_oauth_clients ("userId");
create index auth_oauth_client_resources_client_id_idx on auth_oauth_client_resources ("clientId");
create index auth_oauth_client_resources_resource_id_idx on auth_oauth_client_resources ("resourceId");
create index auth_oauth_refresh_tokens_client_id_idx on auth_oauth_refresh_tokens ("clientId");
create index auth_oauth_refresh_tokens_session_id_idx on auth_oauth_refresh_tokens ("sessionId");
create index auth_oauth_refresh_tokens_user_id_idx on auth_oauth_refresh_tokens ("userId");
create index auth_oauth_refresh_tokens_authorization_code_id_idx on auth_oauth_refresh_tokens ("authorizationCodeId");
create index auth_oauth_access_tokens_client_id_idx on auth_oauth_access_tokens ("clientId");
create index auth_oauth_access_tokens_session_id_idx on auth_oauth_access_tokens ("sessionId");
create index auth_oauth_access_tokens_user_id_idx on auth_oauth_access_tokens ("userId");
create index auth_oauth_access_tokens_authorization_code_id_idx on auth_oauth_access_tokens ("authorizationCodeId");
create index auth_oauth_access_tokens_refresh_id_idx on auth_oauth_access_tokens ("refreshId");
create index auth_oauth_consents_client_id_idx on auth_oauth_consents ("clientId");
create index auth_oauth_consents_user_id_idx on auth_oauth_consents ("userId");

-- Preserve the public client ID already compiled into existing macOS builds.
insert into auth_oauth_resources (
  id, identifier, name, "accessTokenTtl", "refreshTokenTtl", "allowedScopes",
  "dpopBoundAccessTokensRequired", disabled, "createdAt", "updatedAt",
  "policyVersion"
) values (
  'pressay-api-resource', 'https://api.press-say.app', 'Pressay API', 900,
  2592000, '["openid","profile","email","offline_access"]'::jsonb,
  false, false, current_timestamp, current_timestamp, 1
);

insert into auth_oauth_clients (
  id, "clientId", "clientSecret", disabled, "skipConsent", "enableEndSession",
  scopes, "createdAt", "updatedAt", name, uri, "redirectUris",
  "tokenEndpointAuthMethod", "applicationType", "grantTypes", "responseTypes",
  "requirePKCE", "dpopBoundAccessTokens"
) values (
  'pressay-macos-client', 'w9ckUgrcFp7H7wNV', null, false, true, true,
  '["openid","profile","email","offline_access"]'::jsonb,
  current_timestamp, current_timestamp, 'Pressay for macOS',
  'https://press-say.app', '["pressay://oauth/callback"]'::jsonb,
  'none', 'native', '["authorization_code","refresh_token"]'::jsonb,
  '["code"]'::jsonb, true, false
);

insert into auth_oauth_client_resources (
  id, "clientId", "resourceId", "createdAt"
) values (
  'pressay-macos-api-resource', 'w9ckUgrcFp7H7wNV',
  'https://api.press-say.app', current_timestamp
);

comment on table auth_users is
  'Self-hosted Better Auth identities. IDs may preserve imported Clerk subjects during coexistence.';
comment on table auth_oauth_clients is
  'OAuth 2.1 clients issued by Pressay; native public clients must use Authorization Code plus PKCE.';

commit;
