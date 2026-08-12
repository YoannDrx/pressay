begin;

alter table referral_rewards
  add column qualifying_invoice_id text,
  add column qualifying_payment_intent_id text,
  add column qualifying_charge_id text,
  add column extension_base_at timestamptz,
  add column attempt_count integer not null default 0 check (attempt_count >= 0),
  add column last_attempt_at timestamptz;

alter table entitlement_grants
  add column referral_reward_id uuid unique references referral_rewards(id) on delete set null;

create index referral_rewards_qualifying_charge_idx
  on referral_rewards (qualifying_charge_id)
  where status = 'applied' and qualifying_charge_id is not null;

create index referral_rewards_qualifying_payment_intent_idx
  on referral_rewards (qualifying_payment_intent_id)
  where status = 'applied' and qualifying_payment_intent_id is not null;

comment on column referral_rewards.qualifying_invoice_id is
  'Invoice whose first paid subscription payment qualified the referral reward.';
comment on column referral_rewards.qualifying_payment_intent_id is
  'PaymentIntent used to scope refund and dispute reversals to the qualifying payment only.';
comment on column referral_rewards.qualifying_charge_id is
  'Charge used to scope refund and dispute reversals to the qualifying payment only.';
comment on column referral_rewards.extension_base_at is
  'Original subscription billing boundary restored if a billing extension is reversed.';

commit;
