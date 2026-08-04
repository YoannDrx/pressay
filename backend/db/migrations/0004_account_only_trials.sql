begin;

alter table account_trials
  alter column device_id drop not null;

comment on column account_trials.device_id is
  'Optional for trials started on the website; native checkouts bind the same account-level trial to a registered Mac when available.';

commit;
