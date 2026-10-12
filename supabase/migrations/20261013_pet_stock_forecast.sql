-- Aplicar DEPOIS de 20261012_compras_estoque_pets.sql no SQL Editor.
-- Transação atômica e reaplicável; não remove pets, seções ou produtos existentes.
begin;
alter table public.tefalei_stock_items
 add column if not exists average_consumption numeric not null default 0 check (average_consumption >= 0),
 add column if not exists consumption_period_days integer not null default 1 check (consumption_period_days > 0),
 add column if not exists alert_days integer not null default 3 check (alert_days >= 0);

-- Invoker mantém as políticas de acesso do relacionamento. O lock serializa
-- criações concorrentes para o mesmo pet sem excluir seções antigas duplicadas.
create or replace function public.tefalei_ensure_pet_stock_section()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
 perform pg_advisory_xact_lock(hashtextextended(new.id::text, 0));
 if not exists (select 1 from public.tefalei_stock_sections where pet_id = new.id and relationship_id = new.relationship_id) then
  insert into public.tefalei_stock_sections(relationship_id, pet_id, name, created_by)
  values (new.relationship_id, new.id, new.name, new.created_by);
 end if;
 return new;
end;
$$;
drop trigger if exists tefalei_pet_stock_section on public.tefalei_pets;
create trigger tefalei_pet_stock_section after insert on public.tefalei_pets
 for each row execute function public.tefalei_ensure_pet_stock_section();
-- Bloqueia novas inserções de pets/seções durante o preenchimento inicial.
lock table public.tefalei_pets, public.tefalei_stock_sections in share row exclusive mode;
insert into public.tefalei_stock_sections(relationship_id,pet_id,name,created_by)
 select p.relationship_id,p.id,p.name,p.created_by from public.tefalei_pets p
 where not exists (select 1 from public.tefalei_stock_sections s where s.pet_id=p.id and s.relationship_id=p.relationship_id);

-- Impede vínculos com pets/seções de outro relacionamento, inclusive por API.
create or replace function public.tefalei_validate_stock_link()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
 if tg_table_name = 'tefalei_stock_sections' then
  if new.pet_id is not null and not exists(select 1 from public.tefalei_pets p where p.id=new.pet_id and p.relationship_id=new.relationship_id) then
   raise exception 'Pet não pertence ao relacionamento';
  end if;
 else
  if new.section_id is not null and not exists(select 1 from public.tefalei_stock_sections s where s.id=new.section_id and s.relationship_id=new.relationship_id) then
   raise exception 'Seção não pertence ao relacionamento';
  end if;
 end if;
 return new;
end;
$$;
drop trigger if exists tefalei_validate_pet_link on public.tefalei_stock_sections;
create trigger tefalei_validate_pet_link before insert or update on public.tefalei_stock_sections for each row execute function public.tefalei_validate_stock_link();
drop trigger if exists tefalei_validate_section_link on public.tefalei_stock_items;
create trigger tefalei_validate_section_link before insert or update on public.tefalei_stock_items for each row execute function public.tefalei_validate_stock_link();
drop trigger if exists tefalei_validate_section_link on public.tefalei_shopping_items;
create trigger tefalei_validate_section_link before insert or update on public.tefalei_shopping_items for each row execute function public.tefalei_validate_stock_link();
commit;
