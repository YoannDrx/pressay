begin;

alter table billing_events
  alter column processed_at drop not null;

comment on column billing_events.processed_at is
  'Null while a signed provider event is pending or being retried; populated after processing, ignoring, or a failed attempt.';

commit;
