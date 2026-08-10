begin;

alter table admin_audit_log
  drop constraint if exists admin_audit_log_actor_account_id_fkey;

drop trigger if exists admin_audit_log_append_only on admin_audit_log;
drop function if exists prevent_admin_audit_log_mutation();
drop rule if exists admin_audit_log_no_update on admin_audit_log;
drop rule if exists admin_audit_log_no_delete on admin_audit_log;

alter table admin_audit_log enable row level security;
alter table admin_audit_log force row level security;

drop policy if exists admin_audit_log_select on admin_audit_log;
drop policy if exists admin_audit_log_insert on admin_audit_log;

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

comment on table admin_audit_log is
  'Append-only record of privileged actions. Row security and rewrite rules permit SELECT and INSERT only; actor IDs are retained after account deletion.';

commit;
