begin;
create table if not exists public.tefalei_favorite_things (
 id uuid primary key default gen_random_uuid(),
 relationship_id uuid not null references public.relationships(id) on delete cascade,
 title text not null check(length(trim(title)) between 1 and 180),
 brand text not null default '' check(length(brand)<=180),
 photo_path text check(photo_path is null or photo_path like relationship_id::text||'/%'),
 archived boolean not null default false,
 created_at timestamptz not null default now()
);
create index if not exists tf_favorite_things_relationship on public.tefalei_favorite_things(relationship_id,title) where not archived;
alter table public.tefalei_favorite_things enable row level security;
create policy tf_favorite_things_members on public.tefalei_favorite_things for all to authenticated
 using(exists(select 1 from public.relationship_members m where m.relationship_id=tefalei_favorite_things.relationship_id and m.user_id=(select auth.uid())))
 with check(exists(select 1 from public.relationship_members m where m.relationship_id=tefalei_favorite_things.relationship_id and m.user_id=(select auth.uid())));
revoke all on public.tefalei_favorite_things from anon,authenticated;
grant select,insert,update on public.tefalei_favorite_things to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('tefalei-things','tefalei-things',false,3145728,array['image/jpeg']) on conflict(id) do nothing;
create policy tf_things_photo_read on storage.objects for select to authenticated
 using(bucket_id='tefalei-things' and exists(select 1 from public.relationship_members m where m.relationship_id::text=(storage.foldername(name))[1] and m.user_id=(select auth.uid())));
create policy tf_things_photo_insert on storage.objects for insert to authenticated
 with check(bucket_id='tefalei-things' and exists(select 1 from public.relationship_members m where m.relationship_id::text=(storage.foldername(name))[1] and m.user_id=(select auth.uid())));
commit;
