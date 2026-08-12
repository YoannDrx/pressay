begin;

-- Better Auth 1.7 keys OAuth accounts by the provider's stable issuer and
-- subject. This additive repair also upgrades databases where migration 0009
-- was applied before the issuer field became part of the core account schema.
alter table auth_accounts add column if not exists issuer text;

update auth_accounts
set issuer = case
  when "providerId" = 'google' then 'https://accounts.google.com'
  when "providerId" = 'credential' then 'local:credential'
  else 'local:oauth:' || "providerId"
end
where issuer is null;

alter table auth_accounts alter column issuer set not null;
alter table auth_accounts
  drop constraint if exists "auth_accounts_providerId_accountId_key";
alter table auth_accounts
  drop constraint if exists "auth_accounts_issuer_accountId_key";

create unique index if not exists auth_accounts_issuer_account_id_uq
  on auth_accounts (issuer, "accountId");

commit;
