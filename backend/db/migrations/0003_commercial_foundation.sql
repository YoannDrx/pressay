begin;

alter table devices
  add column if not exists revoked_at timestamptz;

alter table entitlements
  add column if not exists trial_end timestamptz;

alter table entitlements
  add column if not exists founding_claimed_at timestamptz;

alter table entitlements
  add column if not exists provider_event_created_at timestamptz;

create table if not exists founding_claims (
  marker_sha256 text primary key check (length(marker_sha256) = 64),
  account_id uuid not null unique references accounts(id) on delete cascade,
  device_id uuid references devices(id) on delete set null,
  app_version text not null,
  claimed_at timestamptz not null default now()
);

create table if not exists account_trials (
  account_id uuid primary key references accounts(id) on delete cascade,
  device_id uuid not null references devices(id) on delete restrict,
  started_at timestamptz not null default now(),
  ends_at timestamptz not null,
  check (ends_at > started_at)
);

create table if not exists api_rate_limits (
  key_sha256 text not null check (length(key_sha256) = 64),
  window_start timestamptz not null,
  request_count integer not null default 1 check (request_count > 0),
  primary key (key_sha256, window_start)
);

create index if not exists devices_active_idx
  on devices (account_id, last_seen_at desc)
  where revoked_at is null;

create index if not exists api_rate_limits_expiry_idx
  on api_rate_limits (window_start);

comment on table founding_claims is
  'Stores only SHA-256 hashes of opaque 1.2.3 eligibility markers; raw markers never leave request processing.';

commit;
