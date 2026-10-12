-- Execute no SQL Editor do Supabase antes de usar Compras e Estoque.
create table if not exists public.tefalei_pets (
 id uuid primary key default gen_random_uuid(),
 relationship_id uuid not null references public.relationships(id) on delete cascade,
 name text not null check(length(trim(name)) between 1 and 100),
 birthday date, species text not null default 'Cachorro',
 breed text, notes text, created_by uuid not null default auth.uid(),
 created_at timestamptz not null default now()
);
create table if not exists public.tefalei_stock_sections (
 id uuid primary key default gen_random_uuid(),
 relationship_id uuid not null references public.relationships(id) on delete cascade,
 name text not null check(length(trim(name)) between 1 and 100),
 pet_id uuid references public.tefalei_pets(id) on delete set null,
 created_by uuid not null default auth.uid(),
 created_at timestamptz not null default now()
);
create table if not exists public.tefalei_shopping_items (
 id uuid primary key default gen_random_uuid(),
 relationship_id uuid not null references public.relationships(id) on delete cascade,
 title text not null check(length(trim(title)) between 1 and 180),
 section_id uuid references public.tefalei_stock_sections(id) on delete set null,
 quantity numeric not null default 1 check(quantity >= 0),
 unit text not null default 'un.',
 purchased boolean not null default false,
 purchased_by uuid references auth.users(id),
 purchased_at timestamptz,
 created_by uuid not null default auth.uid(),
 created_at timestamptz not null default now()
);
create table if not exists public.tefalei_stock_items (
 id uuid primary key default gen_random_uuid(),
 relationship_id uuid not null references public.relationships(id) on delete cascade,
 section_id uuid not null references public.tefalei_stock_sections(id) on delete cascade,
 title text not null check(length(trim(title)) between 1 and 180),
 quantity numeric not null default 0 check(quantity >= 0),
 unit text not null default 'un.',
 minimum numeric not null default 0 check(minimum >= 0),
 updated_at timestamptz not null default now(),
 unique(section_id,title)
);
create index if not exists idx_tf_pets_rel on public.tefalei_pets(relationship_id);
create index if not exists idx_tf_sections_rel on public.tefalei_stock_sections(relationship_id);
create index if not exists idx_tf_shopping_rel on public.tefalei_shopping_items(relationship_id,created_at);
create index if not exists idx_tf_stock_rel on public.tefalei_stock_items(relationship_id);
alter table public.tefalei_pets enable row level security;
alter table public.tefalei_stock_sections enable row level security;
alter table public.tefalei_shopping_items enable row level security;
alter table public.tefalei_stock_items enable row level security;
-- Isolamento por relacionamento: membros ativos podem consultar e alterar registros do seu relacionamento.
do $$ declare t text; begin
 foreach t in array array['tefalei_pets','tefalei_stock_sections','tefalei_shopping_items','tefalei_stock_items'] loop
  execute format('drop policy if exists "tf_members_access" on public.%I',t);
  execute format('create policy "tf_members_access" on public.%I for all to authenticated using (exists (select 1 from public.relationship_members rm where rm.relationship_id = %I.relationship_id and rm.user_id = (select auth.uid()))) with check (exists (select 1 from public.relationship_members rm where rm.relationship_id = %I.relationship_id and rm.user_id = (select auth.uid())))',t,t,t);
 end loop;
end $$;
