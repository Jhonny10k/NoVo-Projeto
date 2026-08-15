-- 2026-08-15 — Fundação empresarial de múltiplas unidades e associação de membros.
-- Esta migration NÃO altera silenciosamente o escopo dos registros comerciais existentes.

update public.plans
set entitlements=coalesce(entitlements,'{}'::jsonb)||'{"multi_unit":false}'::jsonb,
    limits='{"units":5}'::jsonb||coalesce(limits,'{}'::jsonb)
where not coalesce(entitlements,'{}'::jsonb) ? 'multi_unit';

create table public.organization_units (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check(char_length(name) between 2 and 120),
  code text not null check(code ~ '^[A-Z0-9_-]{2,20}$'),
  phone text,
  email text,
  address text,
  city text,
  state text check(state is null or char_length(state)=2),
  timezone text not null default 'America/Sao_Paulo' check(char_length(timezone) between 3 and 80),
  status text not null default 'active' check(status in ('active','inactive')),
  is_headquarters boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,code),
  unique(organization_id,id)
);
create unique index organization_units_one_headquarters_idx on public.organization_units(organization_id) where is_headquarters=true and status='active';
create trigger organization_units_set_updated_at before update on public.organization_units for each row execute procedure public.set_updated_at();
alter table public.organization_units enable row level security;
create policy organization_units_select_member on public.organization_units for select to authenticated
using(public.is_org_member(organization_id) and public.has_feature(organization_id,'multi_unit'));
create policy organization_units_insert_admin on public.organization_units for insert to authenticated
with check(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'multi_unit'));
create policy organization_units_update_admin on public.organization_units for update to authenticated
using(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'multi_unit'))
with check(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'multi_unit'));
create policy organization_units_delete_admin on public.organization_units for delete to authenticated
using(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'multi_unit'));

create table public.organization_member_units (
  organization_id uuid not null,
  user_id uuid not null,
  unit_id uuid not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key(organization_id,user_id,unit_id),
  foreign key(organization_id,user_id) references public.organization_members(organization_id,user_id) on delete cascade,
  foreign key(organization_id,unit_id) references public.organization_units(organization_id,id) on delete cascade
);
create index organization_member_units_unit_idx on public.organization_member_units(organization_id,unit_id);
alter table public.organization_member_units enable row level security;
create policy organization_member_units_select on public.organization_member_units for select to authenticated
using(public.has_feature(organization_id,'multi_unit') and (user_id=auth.uid() or public.has_org_role(organization_id,array['owner','admin'])));
create policy organization_member_units_insert_admin on public.organization_member_units for insert to authenticated
with check(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'multi_unit'));
create policy organization_member_units_delete_admin on public.organization_member_units for delete to authenticated
using(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'multi_unit'));

create or replace function public.member_can_access_unit(p_organization_id uuid,p_unit_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select case
    when p_unit_id is null then public.is_org_member(p_organization_id)
    when public.has_org_role(p_organization_id,array['owner','admin']) then true
    else exists(select 1 from public.organization_member_units mu where mu.organization_id=p_organization_id and mu.user_id=auth.uid() and mu.unit_id=p_unit_id)
  end;
$$;
revoke all on function public.member_can_access_unit(uuid,uuid) from public;
grant execute on function public.member_can_access_unit(uuid,uuid) to authenticated;

create or replace function public.list_enterprise_units(p_organization_id uuid)
returns table(id uuid,name text,code text,phone text,email text,address text,city text,state text,timezone text,status text,is_headquarters boolean,assigned_members bigint,created_at timestamptz)
language sql stable security definer set search_path=public as $$
  select u.id,u.name,u.code,u.phone,u.email,u.address,u.city,u.state,u.timezone,u.status,u.is_headquarters,
    (select count(*) from public.organization_member_units mu where mu.organization_id=u.organization_id and mu.unit_id=u.id),u.created_at
  from public.organization_units u
  where u.organization_id=p_organization_id and public.is_org_member(p_organization_id) and public.has_feature(p_organization_id,'multi_unit')
  order by u.is_headquarters desc,u.name;
$$;
revoke all on function public.list_enterprise_units(uuid) from public;
grant execute on function public.list_enterprise_units(uuid) to authenticated;
