begin;
alter table public.tefalei_agenda_items add column if not exists repeat_interval_weeks integer not null default 1 check(repeat_interval_weeks between 1 and 52), add column if not exists repeat_anchor_date date;
commit;
