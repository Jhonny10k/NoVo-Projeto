-- 2026-08-15 — White-label e domínios customizados verificados pelo provider de deploy.

update public.plans
set entitlements = coalesce(entitlements,'{}'::jsonb) || '{"white_label":false}'::jsonb,
    limits = '{"custom_domains":1}'::jsonb || coalesce(limits,'{}'::jsonb)
where not coalesce(entitlements,'{}'::jsonb) ? 'white_label';

create table public.organization_branding (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  brand_name text check(brand_name is null or char_length(brand_name) between 2 and 100),
  logo_url text,
  favicon_url text,
  primary_color text check(primary_color is null or primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  support_email text,
  hide_platform_branding boolean not null default true,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.organization_branding enable row level security;
create policy organization_branding_select_member on public.organization_branding for select to authenticated
using(public.is_org_member(organization_id) and public.has_feature(organization_id,'white_label'));
create policy organization_branding_insert_admin on public.organization_branding for insert to authenticated
with check(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'white_label'));
create policy organization_branding_update_admin on public.organization_branding for update to authenticated
using(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'white_label'))
with check(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'white_label'));

create table public.custom_domains (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  hostname text not null unique check(hostname=lower(hostname) and char_length(hostname) between 4 and 253),
  status text not null default 'pending' check(status in ('pending','verifying','active','error','disabled')),
  provider text not null default 'vercel' check(provider in ('vercel')),
  provider_verified boolean not null default false,
  provider_data jsonb not null default '{}'::jsonb check(jsonb_typeof(provider_data)='object'),
  is_primary boolean not null default false,
  last_checked_at timestamptz,
  last_error text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index custom_domains_org_idx on public.custom_domains(organization_id,created_at desc);
create unique index custom_domains_one_primary_idx on public.custom_domains(organization_id) where is_primary=true and status='active';
create trigger custom_domains_set_updated_at before update on public.custom_domains for each row execute procedure public.set_updated_at();
alter table public.custom_domains enable row level security;
-- Gestão server-side; leitura segura por RPC para não expor provider_data completo.

create or replace function public.list_custom_domains(p_organization_id uuid)
returns table(id uuid,hostname text,status text,provider_verified boolean,is_primary boolean,verification jsonb,last_checked_at timestamptz,last_error text,created_at timestamptz)
language sql stable security definer set search_path=public as $$
  select d.id,d.hostname,d.status,d.provider_verified,d.is_primary,coalesce(d.provider_data->'verification','[]'::jsonb),d.last_checked_at,d.last_error,d.created_at
  from public.custom_domains d
  where d.organization_id=p_organization_id
    and public.has_org_role(p_organization_id,array['owner','admin'])
    and public.has_feature(p_organization_id,'white_label')
  order by d.is_primary desc,d.created_at desc;
$$;
revoke all on function public.list_custom_domains(uuid) from public;
grant execute on function public.list_custom_domains(uuid) to authenticated;

create or replace function public.resolve_public_custom_domain(p_hostname text)
returns text
language sql stable security definer set search_path=public as $$
  select o.slug
  from public.custom_domains d join public.organizations o on o.id=d.organization_id
  where d.hostname=lower(trim(p_hostname)) and d.status='active' and d.provider_verified=true and o.status='active'
    and public.service_organization_has_feature(o.id,'white_label')
  limit 1;
$$;
revoke all on function public.resolve_public_custom_domain(text) from public;
grant execute on function public.resolve_public_custom_domain(text) to anon,authenticated;

create or replace function public.get_public_branding(p_slug text)
returns jsonb
language sql stable security definer set search_path=public as $$
  select case when public.service_organization_has_feature(o.id,'white_label') then jsonb_build_object(
    'brand_name',b.brand_name,'logo_url',b.logo_url,'favicon_url',b.favicon_url,'primary_color',b.primary_color,
    'hide_platform_branding',coalesce(b.hide_platform_branding,true),
    'primary_domain',(select d.hostname from public.custom_domains d where d.organization_id=o.id and d.status='active' and d.provider_verified=true order by d.is_primary desc,d.created_at limit 1)
  ) else '{}'::jsonb end
  from public.organizations o left join public.organization_branding b on b.organization_id=o.id
  where o.slug=p_slug and o.status='active' limit 1;
$$;
revoke all on function public.get_public_branding(text) from public;
grant execute on function public.get_public_branding(text) to anon,authenticated;
