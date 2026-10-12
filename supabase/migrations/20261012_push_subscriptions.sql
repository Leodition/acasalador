-- Apply in Supabase SQL editor before enabling Web Push.
create table if not exists public.tefalei_push_subscriptions (
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth_key text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, endpoint)
);
alter table public.tefalei_push_subscriptions enable row level security;
revoke all on public.tefalei_push_subscriptions from anon;
grant select, insert, update, delete on public.tefalei_push_subscriptions to authenticated;
drop policy if exists "Users manage own push subscriptions" on public.tefalei_push_subscriptions;
create policy "Users manage own push subscriptions" on public.tefalei_push_subscriptions
for all to authenticated using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));
create index if not exists tefalei_push_subscriptions_user_idx
on public.tefalei_push_subscriptions(user_id);
-- Never expose subscription credentials to other users.
-- The push sender must use a trusted server with service-role access.
