begin;

alter table billing_customers
  add column if not exists stripe_subscription_id text unique;

alter table billing_customers
  add column if not exists last_checkout_at timestamptz;

create index if not exists billing_customers_subscription_idx
  on billing_customers (stripe_subscription_id)
  where stripe_subscription_id is not null;

comment on column billing_customers.stripe_subscription_id is
  'Server-side Stripe identifier only. No payment instrument data is stored.';

commit;
