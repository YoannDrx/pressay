begin;

create extension if not exists pgcrypto;

create table accounts (
  id uuid primary key default gen_random_uuid(),
  auth_subject text not null unique,
  email text,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table devices (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references accounts(id) on delete cascade,
  device_identifier text not null,
  platform text not null check (platform in ('macos')),
  app_version text not null,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (account_id, device_identifier)
);

create table entitlements (
  account_id uuid primary key references accounts(id) on delete cascade,
  plan_code text not null default 'free'
    check (plan_code in ('free', 'pro_byok', 'pro_cloud', 'lifetime_byok', 'team')),
  status text not null default 'active'
    check (status in ('active', 'trialing', 'past_due', 'canceled', 'expired')),
  source text not null default 'grant'
    check (source in ('grant', 'stripe', 'app_store', 'legacy')),
  current_period_start timestamptz,
  current_period_end timestamptz,
  updated_at timestamptz not null default now()
);

create table billing_customers (
  account_id uuid primary key references accounts(id) on delete cascade,
  stripe_customer_id text unique,
  app_store_original_transaction_id text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table billing_events (
  provider text not null check (provider in ('stripe', 'app_store')),
  provider_event_id text not null,
  event_type text not null,
  payload_sha256 text not null,
  processed_at timestamptz not null default now(),
  primary key (provider, provider_event_id)
);

create table usage_events (
  id bigserial primary key,
  account_id uuid not null references accounts(id) on delete cascade,
  idempotency_key uuid not null,
  transcription_seconds integer not null default 0 check (transcription_seconds >= 0),
  transformations integer not null default 0 check (transformations >= 0),
  cloud_characters integer not null default 0 check (cloud_characters >= 0),
  created_at timestamptz not null default now(),
  unique (account_id, idempotency_key)
);

create table usage_monthly (
  account_id uuid not null references accounts(id) on delete cascade,
  period_start date not null,
  transcription_seconds bigint not null default 0 check (transcription_seconds >= 0),
  transformations bigint not null default 0 check (transformations >= 0),
  cloud_characters bigint not null default 0 check (cloud_characters >= 0),
  updated_at timestamptz not null default now(),
  primary key (account_id, period_start),
  check (period_start = date_trunc('month', period_start)::date)
);

create table sync_objects (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references accounts(id) on delete cascade,
  object_type text not null check (object_type in ('mode', 'profile', 'preference')),
  client_object_id uuid not null,
  ciphertext bytea not null,
  nonce bytea not null,
  algorithm text not null default 'AES-GCM-256',
  schema_version integer not null default 1 check (schema_version > 0),
  client_updated_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (account_id, object_type, client_object_id)
);

create table product_events (
  id bigserial primary key,
  account_id uuid references accounts(id) on delete set null,
  anonymous_id uuid,
  event_name text not null,
  properties jsonb not null default '{}'::jsonb,
  app_version text,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  check (account_id is not null or anonymous_id is not null),
  check (jsonb_typeof(properties) = 'object')
);

create table deletion_jobs (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references accounts(id) on delete cascade,
  requested_at timestamptz not null default now(),
  execute_after timestamptz not null,
  completed_at timestamptz,
  status text not null default 'pending'
    check (status in ('pending', 'running', 'completed', 'failed')),
  unique (account_id)
);

create index devices_last_seen_idx on devices (account_id, last_seen_at desc);
create index usage_events_created_idx on usage_events (account_id, created_at desc);
create index sync_objects_changes_idx on sync_objects (account_id, updated_at, id);
create index product_events_name_time_idx on product_events (event_name, occurred_at desc);
create index deletion_jobs_due_idx on deletion_jobs (status, execute_after)
  where status = 'pending';

comment on table sync_objects is
  'Opaque end-to-end encrypted settings only. Never store audio, transcription text, selections, or BYOK API keys.';
comment on table product_events is
  'Allowlisted product telemetry only. Event properties must never contain dictated or selected text.';

commit;
