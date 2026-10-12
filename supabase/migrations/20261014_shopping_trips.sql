begin;
alter table public.tefalei_shopping_items add column if not exists purchased_participants uuid[];
alter table public.tefalei_system_notifications add column if not exists payload jsonb not null default '{}'::jsonb, add column if not exists dedupe_key text;
update public.tefalei_system_notifications set dedupe_key=user_id::text||':work_schedule_setup' where kind='work_schedule_setup' and dedupe_key is null;
alter table public.tefalei_system_notifications drop constraint if exists tefalei_system_notifications_user_id_kind_key;
alter table public.tefalei_system_notifications drop constraint if exists tefalei_system_notifications_kind_check;
alter table public.tefalei_system_notifications add constraint tefalei_system_notifications_kind_check check(kind in ('work_schedule_setup','shopping_started','shopping_completed'));
create unique index if not exists tf_system_notice_dedupe on public.tefalei_system_notifications(dedupe_key);
create table if not exists public.tefalei_shopping_trips(
 id uuid primary key default gen_random_uuid(), relationship_id uuid not null references public.relationships(id) on delete cascade,
 initiator_id uuid not null references auth.users(id), participant_ids uuid[] not null, picked_ids uuid[] not null default '{}',
 status text not null default 'open' check(status in ('open','completed','cancelled')), receipt jsonb not null default '[]'::jsonb,
 created_at timestamptz not null default now(), completed_at timestamptz
);
alter table public.tefalei_shopping_trips enable row level security;
drop policy if exists tf_trip_read on public.tefalei_shopping_trips;
create policy tf_trip_read on public.tefalei_shopping_trips for select to authenticated
 using((select auth.uid())=any(participant_ids) and exists(select 1 from public.relationship_members m where m.relationship_id=tefalei_shopping_trips.relationship_id and m.user_id=(select auth.uid())));
revoke all on public.tefalei_shopping_trips from anon,authenticated;
grant select on public.tefalei_shopping_trips to authenticated;
create or replace function public.tefalei_queue_work_schedule_notices()
returns void language sql security definer set search_path='' as $$
 insert into public.tefalei_system_notifications(user_id,kind,title,dedupe_key)
 select u.id,'work_schedule_setup','Cadastre seus horários de trabalho para organizar melhor a rotina de vocês.',u.id::text||':work_schedule_setup'
 from auth.users u join public.profiles p on p.id=u.id where u.created_at<=now()-interval '2 days' and u.email_confirmed_at is not null
 and not exists(select 1 from public.tefalei_agenda_items a where a.user_id=u.id and a.kind='routine' and a.category='work' and not coalesce(a.archived,false))
 on conflict(dedupe_key) do nothing;
$$;
create or replace function public.tefalei_system_notifications_for_me()
returns setof public.tefalei_system_notifications language sql stable security invoker set search_path='' as $$
 select n.* from public.tefalei_system_notifications n where n.user_id=(select auth.uid())
 and (n.kind<>'work_schedule_setup' or not exists(select 1 from public.tefalei_agenda_items a where a.user_id=n.user_id and a.kind='routine' and a.category='work' and not coalesce(a.archived,false))) order by n.created_at desc;
$$;
create or replace function public.tefalei_start_shopping_trip(p_relationship uuid,p_participants uuid[])
returns public.tefalei_shopping_trips language plpgsql security definer set search_path='' as $$
declare who uuid:=auth.uid(); chosen uuid[]; trip public.tefalei_shopping_trips; names text; total integer;
begin
 if who is null then raise exception 'Entre na conta'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_relationship::text,0));
 select array_agg(distinct x order by x) into chosen from unnest(p_participants) x;
 if chosen is null or not(who=any(chosen)) or not exists(select 1 from public.relationship_members where relationship_id=p_relationship and user_id=who)
 or exists(select 1 from unnest(chosen) x where not exists(select 1 from public.relationship_members where relationship_id=p_relationship and user_id=x)) then raise exception 'Participantes inválidos'; end if;
 select * into trip from public.tefalei_shopping_trips where relationship_id=p_relationship and status='open' and participant_ids && chosen limit 1;
 if found then if trip.participant_ids=chosen then return trip; end if; raise exception 'Já existe uma compra em andamento para um dos participantes'; end if;
 insert into public.tefalei_shopping_trips(relationship_id,initiator_id,participant_ids) values(p_relationship,who,chosen) returning * into trip;
 select string_agg(coalesce(nullif(p.como_chamar,''),nullif(p.nome,''),'Participante'),' e ' order by p.id) into names from public.profiles p where p.id=any(chosen);
 select count(*) into total from public.relationship_members where relationship_id=p_relationship;
 if cardinality(chosen)<total then
 insert into public.tefalei_system_notifications(user_id,kind,title,payload,dedupe_key)
 select m.user_id,'shopping_started',names||case when cardinality(chosen)=1 then ' está fazendo compras.' else ' estão fazendo compras.' end,
 jsonb_build_object('trip_id',trip.id,'participant_ids',chosen),trip.id::text||':started:'||m.user_id::text
 from public.relationship_members m where m.relationship_id=p_relationship and not(m.user_id=any(chosen));
 end if;
 return trip;
end;$$;
create or replace function public.tefalei_pick_shopping_item(p_trip uuid,p_item uuid,p_picked boolean)
returns public.tefalei_shopping_trips language plpgsql security definer set search_path='' as $$
declare trip public.tefalei_shopping_trips;
begin
 select * into trip from public.tefalei_shopping_trips where id=p_trip for update;
 if not found or auth.uid() is null or not(auth.uid()=any(trip.participant_ids)) or not exists(select 1 from public.relationship_members where relationship_id=trip.relationship_id and user_id=auth.uid()) or trip.status<>'open' then raise exception 'Compra indisponível'; end if;
 if not exists(select 1 from public.tefalei_shopping_items where id=p_item and relationship_id=trip.relationship_id and not purchased) then raise exception 'Item indisponível'; end if;
 if p_picked and not(p_item=any(trip.picked_ids)) then trip.picked_ids:=array_append(trip.picked_ids,p_item); elsif not p_picked then trip.picked_ids:=array_remove(trip.picked_ids,p_item); end if;
 update public.tefalei_shopping_trips set picked_ids=trip.picked_ids where id=p_trip;return trip;
end;$$;
create or replace function public.tefalei_finish_shopping_trip(p_trip uuid,p_complete boolean default true)
returns public.tefalei_shopping_trips language plpgsql security definer set search_path='' as $$
declare trip public.tefalei_shopping_trips; names text; bought jsonb;
begin
 select * into trip from public.tefalei_shopping_trips where id=p_trip for update;
 if not found or auth.uid() is null or not(auth.uid()=any(trip.participant_ids)) or not exists(select 1 from public.relationship_members where relationship_id=trip.relationship_id and user_id=auth.uid()) then raise exception 'Compra indisponível'; end if;
 if trip.status<>'open' then return trip; end if;
 if not p_complete then update public.tefalei_shopping_trips set status='cancelled',completed_at=now() where id=p_trip returning * into trip;return trip;end if;
 with changed as(update public.tefalei_shopping_items set purchased=true,purchased_by=auth.uid(),purchased_participants=trip.participant_ids,purchased_at=now() where relationship_id=trip.relationship_id and id=any(trip.picked_ids) and not purchased returning title,quantity,unit,section_id)
 select jsonb_agg(jsonb_build_object('title',c.title,'quantity',c.quantity,'unit',c.unit,'section',s.name) order by c.title) into bought from changed c left join public.tefalei_stock_sections s on s.id=c.section_id;
 if bought is null then raise exception 'Nenhum item marcado para concluir'; end if;
 update public.tefalei_shopping_trips set status='completed',receipt=bought,completed_at=now() where id=p_trip returning * into trip;
 select string_agg(coalesce(nullif(p.como_chamar,''),nullif(p.nome,''),'Participante'),' e ' order by p.id) into names from public.profiles p where p.id=any(trip.participant_ids);
 insert into public.tefalei_system_notifications(user_id,kind,title,payload,dedupe_key)
 select m.user_id,'shopping_completed',names||case when cardinality(trip.participant_ids)=1 then ' fez compras.' else ' fizeram compras.' end,
 jsonb_build_object('trip_id',trip.id,'participant_ids',trip.participant_ids,'items',bought),trip.id::text||':completed:'||m.user_id::text
 from public.relationship_members m where m.relationship_id=trip.relationship_id and m.user_id<>auth.uid();
 return trip;
end;$$;
revoke all on function public.tefalei_start_shopping_trip(uuid,uuid[]),public.tefalei_pick_shopping_item(uuid,uuid,boolean),public.tefalei_finish_shopping_trip(uuid,boolean) from public,anon;
grant execute on function public.tefalei_start_shopping_trip(uuid,uuid[]),public.tefalei_pick_shopping_item(uuid,uuid,boolean),public.tefalei_finish_shopping_trip(uuid,boolean) to authenticated;
commit;
