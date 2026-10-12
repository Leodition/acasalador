begin;
create table if not exists public.tefalei_system_notifications (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check (kind = 'work_schedule_setup'),
 title text not null,
 created_at timestamptz not null default now(),
 unique(user_id,kind)
);
alter table public.tefalei_system_notifications enable row level security;
drop policy if exists tf_system_notices_read on public.tefalei_system_notifications;
create policy tf_system_notices_read on public.tefalei_system_notifications
 for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.tefalei_system_notifications from anon,authenticated;
grant select on public.tefalei_system_notifications to authenticated;
create or replace function public.tefalei_queue_work_schedule_notices()
returns void language sql security definer set search_path = '' as $$
 insert into public.tefalei_system_notifications(user_id,kind,title)
 select u.id,'work_schedule_setup','Cadastre seus horários de trabalho para organizar melhor a rotina de vocês.'
 from auth.users u join public.profiles p on p.id=u.id
 where u.created_at <= now()-interval '2 days'
 and u.email_confirmed_at is not null
 and not exists(select 1 from public.tefalei_agenda_items a where a.user_id=u.id and a.kind='routine' and a.category='work' and not coalesce(a.archived,false))
 on conflict(user_id,kind) do nothing;
$$;
revoke all on function public.tefalei_queue_work_schedule_notices() from public,anon,authenticated;
create or replace function public.tefalei_system_notifications_for_me()
returns setof public.tefalei_system_notifications language sql stable security invoker set search_path = '' as $$
 select n.* from public.tefalei_system_notifications n
 where n.user_id=(select auth.uid())
 and not exists(select 1 from public.tefalei_agenda_items a where a.user_id=n.user_id and a.kind='routine' and a.category='work' and not coalesce(a.archived,false))
 order by n.created_at desc;
$$;
revoke all on function public.tefalei_system_notifications_for_me() from public,anon;
grant execute on function public.tefalei_system_notifications_for_me() to authenticated;
create extension if not exists pg_cron;
select cron.schedule('tefalei-work-schedule-setup','*/15 * * * *','select public.tefalei_queue_work_schedule_notices();');
select public.tefalei_queue_work_schedule_notices();
commit;
