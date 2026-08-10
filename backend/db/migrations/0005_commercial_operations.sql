begin;

create table admin_memberships (
  account_id uuid primary key references accounts(id) on delete cascade,
  role text not null check (role in ('owner', 'support', 'billing', 'viewer')),
  status text not null default 'active' check (status in ('active', 'disabled')),
  granted_by uuid references accounts(id) on delete set null,
  created_at timestamptz not null default now(),
  disabled_at timestamptz,
  check ((status = 'disabled') = (disabled_at is not null))
);

create unique index admin_single_active_owner_idx
  on admin_memberships ((role))
  where role = 'owner' and status = 'active';

create table admin_audit_log (
  id bigserial primary key,
  actor_account_id uuid,
  actor_role text not null check (actor_role in ('owner', 'support', 'billing', 'viewer', 'system')),
  permission text not null,
  action text not null,
  target_type text not null,
  target_id text,
  reason text not null check (length(trim(reason)) >= 3),
  request_id text not null,
  before_state jsonb,
  after_state jsonb,
  result text not null check (result in ('success', 'failed')),
  created_at timestamptz not null default now(),
  check (before_state is null or jsonb_typeof(before_state) = 'object'),
  check (after_state is null or jsonb_typeof(after_state) = 'object')
);

alter table admin_audit_log enable row level security;
alter table admin_audit_log force row level security;

create policy admin_audit_log_select
  on admin_audit_log for select
  using (true);

create policy admin_audit_log_insert
  on admin_audit_log for insert
  with check (true);

create rule admin_audit_log_no_update as
  on update to admin_audit_log do instead nothing;

create rule admin_audit_log_no_delete as
  on delete to admin_audit_log do instead nothing;

create table support_notes (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references accounts(id) on delete cascade,
  category text not null check (category in ('general', 'billing', 'technical', 'privacy', 'security')),
  body text not null check (length(trim(body)) between 1 and 4000),
  created_by uuid references accounts(id) on delete set null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table access_campaigns (
  id uuid primary key default gen_random_uuid(),
  public_id text not null unique,
  kind text not null check (kind in ('access_grant', 'stripe_discount')),
  code_hash text unique check (code_hash is null or length(code_hash) = 64),
  link_token_hash text unique check (link_token_hash is null or length(link_token_hash) = 64),
  code_hint text,
  plan_code text check (plan_code in ('pro_byok', 'lifetime_byok')),
  duration_days integer check (duration_days between 1 and 365),
  is_lifetime boolean not null default false,
  discount_percent integer check (discount_percent between 1 and 100),
  discount_amount integer check (discount_amount > 0),
  currency text not null default 'eur' check (currency ~ '^[a-z]{3}$'),
  max_redemptions integer not null default 1 check (max_redemptions > 0),
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  status text not null default 'active' check (status in ('draft', 'active', 'revoked', 'expired')),
  restricted_email text,
  restricted_domain text,
  internal_note text,
  stripe_promotion_code_id text unique,
  created_by uuid references accounts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at is null or expires_at > starts_at),
  check (not is_lifetime or plan_code = 'lifetime_byok'),
  check (
    (kind = 'access_grant' and plan_code is not null and ((is_lifetime and duration_days is null) or (not is_lifetime and duration_days is not null)) and discount_percent is null and discount_amount is null)
    or
    (kind = 'stripe_discount' and plan_code is null and duration_days is null and not is_lifetime and num_nonnulls(discount_percent, discount_amount) = 1)
  ),
  check (code_hash is not null or link_token_hash is not null or status = 'draft')
);

create table entitlement_grants (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references accounts(id) on delete cascade,
  plan_code text not null check (plan_code in ('pro_byok', 'lifetime_byok')),
  source text not null check (source in ('admin_code', 'referral', 'manual', 'support')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  revoked_at timestamptz,
  campaign_id uuid references access_campaigns(id) on delete set null,
  created_by uuid references accounts(id) on delete set null,
  reason text not null check (length(trim(reason)) >= 3),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at),
  check (jsonb_typeof(metadata) = 'object')
);

create table access_redemptions (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references access_campaigns(id) on delete restrict,
  account_id uuid not null references accounts(id) on delete cascade,
  grant_id uuid references entitlement_grants(id) on delete set null,
  redeemed_at timestamptz not null default now(),
  unique (campaign_id, account_id)
);

create table referral_codes (
  account_id uuid primary key references accounts(id) on delete cascade,
  code text not null unique check (code ~ '^[A-Z0-9]{6,16}$'),
  created_at timestamptz not null default now(),
  disabled_at timestamptz
);

create table referral_attributions (
  id uuid primary key default gen_random_uuid(),
  referrer_account_id uuid not null references accounts(id) on delete cascade,
  referee_account_id uuid not null unique references accounts(id) on delete cascade,
  referral_code text not null references referral_codes(code) on delete restrict,
  source text not null default 'link' check (source in ('link', 'code')),
  status text not null default 'attributed'
    check (status in ('attributed', 'qualified', 'rewarded', 'reversed', 'rejected')),
  risk_status text not null default 'clear' check (risk_status in ('clear', 'review', 'blocked')),
  attributed_at timestamptz not null default now(),
  expires_at timestamptz not null,
  locked_at timestamptz not null default now(),
  rejection_reason text,
  check (referrer_account_id <> referee_account_id),
  check (expires_at > attributed_at)
);

create table referral_rewards (
  id uuid primary key default gen_random_uuid(),
  attribution_id uuid not null references referral_attributions(id) on delete cascade,
  beneficiary_account_id uuid not null references accounts(id) on delete cascade,
  side text not null check (side in ('referrer', 'referee')),
  reward_kind text not null check (reward_kind in ('billing_extension', 'access_grant', 'guest_pass')),
  status text not null default 'pending' check (status in ('pending', 'applied', 'reversed', 'failed')),
  provider_event_id text not null,
  grant_id uuid references entitlement_grants(id) on delete set null,
  campaign_id uuid references access_campaigns(id) on delete set null,
  applied_subscription_id text,
  applied_until timestamptz,
  applied_at timestamptz,
  reversed_at timestamptz,
  last_error_code text,
  created_at timestamptz not null default now(),
  unique (attribution_id, side, provider_event_id)
);

create table download_events (
  id bigserial primary key,
  account_id uuid references accounts(id) on delete set null,
  anonymous_id uuid,
  asset_type text not null default 'dmg' check (asset_type in ('dmg', 'checksum', 'model')),
  app_version text,
  source text,
  campaign text,
  referral_code text,
  platform text check (platform is null or platform in ('macos')),
  architecture text check (architecture is null or architecture in ('arm64', 'x86_64', 'unknown')),
  occurred_at timestamptz not null default now(),
  received_at timestamptz not null default now(),
  check (account_id is not null or anonymous_id is not null)
);

create table billing_transactions (
  id bigserial primary key,
  account_id uuid references accounts(id) on delete set null,
  provider text not null default 'stripe' check (provider in ('stripe', 'app_store')),
  provider_object_id text not null,
  provider_event_id text not null,
  transaction_type text not null check (transaction_type in ('invoice', 'refund', 'dispute', 'lifetime_payment')),
  amount integer not null check (amount >= 0),
  currency text not null check (currency ~ '^[a-z]{3}$'),
  status text not null,
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  unique (provider, provider_object_id, transaction_type)
);

create table checkout_consents (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references accounts(id) on delete cascade,
  idempotency_key uuid not null unique,
  terms_version text not null,
  terms_accepted_at timestamptz not null,
  immediate_performance_consented_at timestamptz not null,
  created_at timestamptz not null default now()
);

alter table billing_events
  add column if not exists status text not null default 'processed'
    check (status in ('received', 'processing', 'processed', 'failed', 'ignored')),
  add column if not exists attempt_count integer not null default 1 check (attempt_count > 0),
  add column if not exists last_error_code text,
  add column if not exists provider_created_at timestamptz;

alter table devices
  add column if not exists distribution_channel text not null default 'direct'
    check (distribution_channel in ('direct', 'app_store')),
  add column if not exists architecture text not null default 'unknown'
    check (architecture in ('arm64', 'x86_64', 'unknown')),
  add column if not exists os_major integer check (os_major is null or os_major between 10 and 99),
  add column if not exists transcription_engine text not null default 'unknown'
    check (transcription_engine in ('openai', 'whisperkit', 'unknown')),
  add column if not exists local_model_id text,
  add column if not exists telemetry_consent boolean not null default false;

alter table billing_customers
  add column if not exists subscription_interval text
    check (subscription_interval is null or subscription_interval in ('monthly', 'annual')),
  add column if not exists subscription_unit_amount integer
    check (subscription_unit_amount is null or subscription_unit_amount >= 0),
  add column if not exists currency text
    check (currency is null or currency ~ '^[a-z]{3}$');

create index admin_audit_log_target_idx on admin_audit_log (target_type, target_id, created_at desc);
create index admin_audit_log_actor_idx on admin_audit_log (actor_account_id, created_at desc);
create index support_notes_account_idx on support_notes (account_id, created_at desc) where deleted_at is null;
create index entitlement_grants_effective_idx on entitlement_grants (account_id, starts_at, ends_at) where revoked_at is null;
create index access_campaigns_status_idx on access_campaigns (status, starts_at, expires_at);
create index referral_attributions_referrer_idx on referral_attributions (referrer_account_id, attributed_at desc);
create index referral_rewards_status_idx on referral_rewards (status, created_at);
create index download_events_time_idx on download_events (occurred_at desc);
create index billing_events_status_idx on billing_events (status, processed_at desc);
create index billing_transactions_account_idx on billing_transactions (account_id, occurred_at desc);
create index billing_transactions_type_time_idx on billing_transactions (transaction_type, occurred_at desc);
create index checkout_consents_account_idx on checkout_consents (account_id, created_at desc);
create index devices_release_idx on devices (app_version, architecture, distribution_channel) where revoked_at is null;

create view admin_user_summary as
select
  a.id,
  a.email,
  a.display_name,
  a.created_at,
  a.updated_at,
  a.deleted_at,
  e.plan_code as subscription_plan,
  e.status as subscription_status,
  e.source as subscription_source,
  e.current_period_end as subscription_end,
  coalesce(device_rollup.active_device_count, 0) as active_device_count,
  device_rollup.last_device_seen_at,
  coalesce(usage_rollup.transcription_seconds, 0) as transcription_seconds,
  coalesce(usage_rollup.transformations, 0) as transformations,
  coalesce(usage_rollup.cloud_characters, 0) as cloud_characters,
  grant_rollup.active_grant_end,
  coalesce(grant_rollup.has_lifetime_grant, false) as has_lifetime_grant
from accounts a
left join entitlements e on e.account_id = a.id
left join lateral (
  select count(*)::integer as active_device_count, max(last_seen_at) as last_device_seen_at
  from devices where account_id = a.id and revoked_at is null
) device_rollup on true
left join lateral (
  select sum(transcription_seconds) as transcription_seconds,
         sum(transformations) as transformations,
         sum(cloud_characters) as cloud_characters
  from usage_monthly where account_id = a.id
) usage_rollup on true
left join lateral (
  select max(ends_at) as active_grant_end,
         bool_or(plan_code = 'lifetime_byok') as has_lifetime_grant
  from entitlement_grants
  where account_id = a.id and revoked_at is null and starts_at <= now()
    and (ends_at is null or ends_at > now())
) grant_rollup on true;

comment on table admin_audit_log is
  'Append-only record of privileged actions. before_state and after_state must be redacted metadata only.';
comment on table download_events is
  'Coarse download metadata only. Never store an IP address, fingerprint, dictated text, audio, clipboard, or BYOK key.';
comment on column devices.local_model_id is
  'Optional allowlisted local model identifier recorded only with product telemetry consent.';

commit;
