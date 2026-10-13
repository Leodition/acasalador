begin;
create table if not exists public.tefalei_individual_money(
 user_id uuid primary key references auth.users(id) on delete cascade,
 income numeric(14,2) not null default 0 check(income>=0),
 categories jsonb not null default '[]'::jsonb check(jsonb_typeof(categories)='array'),
 revision integer not null default 1 check(revision>0),
 updated_at timestamptz not null default now()
);
alter table public.tefalei_individual_money enable row level security;
drop policy if exists tf_money_select on public.tefalei_individual_money;
drop policy if exists tf_money_insert on public.tefalei_individual_money;
drop policy if exists tf_money_update on public.tefalei_individual_money;
create policy tf_money_select on public.tefalei_individual_money for select to authenticated using(user_id=(select auth.uid()));
create policy tf_money_insert on public.tefalei_individual_money for insert to authenticated with check(user_id=(select auth.uid()));
create policy tf_money_update on public.tefalei_individual_money for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
revoke all on public.tefalei_individual_money from anon,authenticated;
grant select,insert,update on public.tefalei_individual_money to authenticated;
create or replace function public.tefalei_save_individual_money(p_income numeric,p_categories jsonb,p_expected_revision integer)
returns public.tefalei_individual_money language plpgsql security invoker set search_path='' as $$
declare row_data public.tefalei_individual_money;
begin
 if auth.uid() is null then raise exception 'Entre na conta';end if;
 if p_income is null or p_income<0 or p_categories is null or jsonb_typeof(p_categories)<>'array' then raise exception 'Dados financeiros inválidos';end if;
 if p_expected_revision=0 then
  insert into public.tefalei_individual_money(user_id,income,categories) values(auth.uid(),p_income,p_categories) on conflict(user_id) do nothing returning * into row_data;
 else
  update public.tefalei_individual_money set income=p_income,categories=p_categories,revision=revision+1,updated_at=now() where user_id=auth.uid() and revision=p_expected_revision returning * into row_data;
 end if;
 if row_data.user_id is null then raise exception 'Os dados foram alterados em outro aparelho. Reabra Nosso dinheiro antes de salvar.';end if;
 return row_data;
end;$$;
revoke all on function public.tefalei_save_individual_money(numeric,jsonb,integer) from public,anon;
grant execute on function public.tefalei_save_individual_money(numeric,jsonb,integer) to authenticated;
commit;
