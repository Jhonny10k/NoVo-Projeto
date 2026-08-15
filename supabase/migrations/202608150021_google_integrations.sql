-- 2026-08-15 — Google Calendar via OAuth/outbox e Google Maps Geocoding v4 server-side.

update public.plans
set entitlements=coalesce(entitlements,'{}'::jsonb)||'{"google_calendar":true,"google_maps":true}'::jsonb
where code in ('professional','ai');

alter table public.integration_connections drop constraint if exists integration_connections_provider_check;
alter table public.integration_connections add constraint integration_connections_provider_check
  check (provider in ('whatsapp_cloud','google_calendar'));

create table public.oauth_states (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('google_calendar')),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
create index oauth_states_expiry_idx on public.oauth_states(expires_at) where used_at is null;
alter table public.oauth_states enable row level security;
-- Sem policies: state OAuth é lido/escrito apenas pelo backend secreto.

create table public.appointment_external_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  appointment_id uuid not null references public.appointments(id) on delete cascade,
  provider text not null check (provider='google_calendar'),
  external_event_id text not null,
  html_link text,
  status text not null default 'active' check(status in ('active','canceled','error')),
  last_synced_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(appointment_id,provider)
);
create trigger appointment_external_events_set_updated_at before update on public.appointment_external_events
for each row execute procedure public.set_updated_at();
alter table public.appointment_external_events enable row level security;
create policy appointment_external_events_select_member on public.appointment_external_events for select to authenticated
using(public.is_org_member(organization_id));
-- Escrita somente pelo worker server-side.

alter table public.organizations
  add column if not exists latitude double precision check(latitude is null or latitude between -90 and 90),
  add column if not exists longitude double precision check(longitude is null or longitude between -180 and 180),
  add column if not exists google_place_id text,
  add column if not exists geocoded_address text,
  add column if not exists geocoded_at timestamptz;

create or replace function public.enqueue_google_calendar_from_event()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_kind text;
begin
  if new.entity_type<>'appointment' or new.entity_id is null then return new; end if;
  if new.event_type not in('appointment_created','appointment_status_changed') then return new; end if;
  if not public.organization_has_entitlement(new.organization_id,'google_calendar') then return new; end if;
  if not exists(select 1 from public.integration_connections c where c.organization_id=new.organization_id and c.provider='google_calendar' and c.status='active') then return new; end if;

  if new.event_type='appointment_status_changed' and lower(coalesce(new.metadata->>'status',''))='canceled' then
    v_kind:='calendar_delete_appointment';
  else
    v_kind:='calendar_upsert_appointment';
  end if;

  insert into public.external_outbox(organization_id,provider,kind,entity_type,entity_id,source_event_id,payload,dedupe_key)
  values(new.organization_id,'google_calendar',v_kind,'appointment',new.entity_id,new.id,new.metadata,
    'google_calendar:'||v_kind||':event:'||new.id::text)
  on conflict(dedupe_key) do nothing;
  return new;
end;
$$;
revoke all on function public.enqueue_google_calendar_from_event() from public,anon,authenticated;
create trigger events_enqueue_google_calendar after insert on public.events
for each row execute procedure public.enqueue_google_calendar_from_event();

-- Reaplica o payload público para expor localização validada sem expor chave do Maps.
create or replace function public.get_public_site(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_org public.organizations%rowtype;v_site public.site_configs%rowtype;v_snapshot jsonb;
begin
  select o.* into v_org from public.organizations o where o.slug=p_slug and o.status='active' limit 1;
  if v_org.id is null or not public.organization_has_entitlement(v_org.id,'site') then return null; end if;
  select s.* into v_site from public.site_configs s where s.organization_id=v_org.id and s.status='published' limit 1;
  if v_site.id is null then return null; end if;
  v_snapshot:=coalesce(v_site.published_snapshot,jsonb_build_object('site',jsonb_build_object('headline',v_site.headline,'subheadline',v_site.subheadline,'about',v_site.about,'primary_color',v_site.primary_color,'cover_image_url',v_site.cover_image_url),'sections','[]'::jsonb));
  return jsonb_build_object(
    'organization',jsonb_build_object('name',v_org.name,'slug',v_org.slug,'segment',v_org.segment,'whatsapp',v_org.whatsapp,'phone',v_org.phone,'city',v_org.city,'state',v_org.state,'address',v_org.address,'latitude',v_org.latitude,'longitude',v_org.longitude,'geocoded_address',v_org.geocoded_address),
    'site',v_snapshot->'site','sections',coalesce(v_snapshot->'sections','[]'::jsonb),
    'products',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'description',p.description,'price_cents',p.price_cents,'promotional_price_cents',p.promotional_price_cents,'image_url',p.image_url) order by p.featured desc,p.created_at desc) from public.products p where p.organization_id=v_org.id and p.available=true),'[]'::jsonb),
    'services',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'description',s.description,'starting_price_cents',s.starting_price_cents,'image_url',s.image_url) order by s.created_at desc) from public.services s where s.organization_id=v_org.id and s.active=true),'[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_public_site(text) from public;
grant execute on function public.get_public_site(text) to anon,authenticated;
