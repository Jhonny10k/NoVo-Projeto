-- 2026-08-15 — Webhooks outbound por tenant usando o external_outbox existente.

update public.plans
set entitlements = coalesce(entitlements,'{}'::jsonb) || '{"outbound_webhooks":false}'::jsonb,
    limits = '{"webhook_endpoints":3}'::jsonb || coalesce(limits,'{}'::jsonb)
where not coalesce(entitlements,'{}'::jsonb) ? 'outbound_webhooks';

create table public.webhook_endpoints (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check(char_length(name) between 2 and 100),
  url text not null check(char_length(url) between 12 and 1000),
  event_types text[] not null check(cardinality(event_types) between 1 and 30),
  status text not null default 'active' check(status in ('active','paused','disabled')),
  signing_secret_prefix text not null check(char_length(signing_secret_prefix) between 8 and 32),
  last_success_at timestamptz,
  last_failure_at timestamptz,
  last_error text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index webhook_endpoints_org_idx on public.webhook_endpoints(organization_id,created_at desc);
create trigger webhook_endpoints_set_updated_at before update on public.webhook_endpoints for each row execute procedure public.set_updated_at();
alter table public.webhook_endpoints enable row level security;
-- Sem policies: edição passa por ações server-side; leitura segura usa RPC sem segredo.

create table public.webhook_endpoint_secrets (
  endpoint_id uuid primary key references public.webhook_endpoints(id) on delete cascade,
  ciphertext text not null,
  iv text not null,
  auth_tag text not null,
  updated_at timestamptz not null default now()
);
alter table public.webhook_endpoint_secrets enable row level security;
-- Sem policies: segredo criptografado ainda é infraestrutura server-only.

create table public.webhook_deliveries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  endpoint_id uuid not null references public.webhook_endpoints(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  event_type text not null,
  status text not null default 'queued' check(status in ('queued','processing','retry','delivered','failed')),
  attempts integer not null default 0 check(attempts>=0),
  response_status integer check(response_status is null or response_status between 100 and 599),
  last_error text,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(endpoint_id,event_id)
);
create index webhook_deliveries_org_created_idx on public.webhook_deliveries(organization_id,created_at desc);
create index webhook_deliveries_endpoint_created_idx on public.webhook_deliveries(endpoint_id,created_at desc);
create trigger webhook_deliveries_set_updated_at before update on public.webhook_deliveries for each row execute procedure public.set_updated_at();
alter table public.webhook_deliveries enable row level security;

alter table public.external_outbox drop constraint if exists external_outbox_provider_check;
alter table public.external_outbox add constraint external_outbox_provider_check
check(provider in ('resend','whatsapp_cloud','google_calendar','client_webhook'));

create or replace function public.enqueue_client_webhooks_from_event()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_endpoint record;v_delivery uuid;
begin
  if not public.service_organization_has_feature(new.organization_id,'outbound_webhooks') then return new; end if;
  for v_endpoint in
    select e.id,e.organization_id from public.webhook_endpoints e
    where e.organization_id=new.organization_id and e.status='active' and new.event_type=any(e.event_types)
  loop
    insert into public.webhook_deliveries(organization_id,endpoint_id,event_id,event_type)
    values(new.organization_id,v_endpoint.id,new.id,new.event_type)
    on conflict(endpoint_id,event_id) do nothing
    returning id into v_delivery;
    if v_delivery is null then select id into v_delivery from public.webhook_deliveries where endpoint_id=v_endpoint.id and event_id=new.id; end if;

    insert into public.external_outbox(organization_id,provider,kind,entity_type,entity_id,source_event_id,payload,dedupe_key)
    values(new.organization_id,'client_webhook',new.event_type,'webhook_delivery',v_delivery,new.id,
      jsonb_build_object(
        'delivery_id',v_delivery,'endpoint_id',v_endpoint.id,'event_id',new.id,'event_type',new.event_type,
        'entity_type',new.entity_type,'entity_id',new.entity_id,'occurred_at',new.created_at,'metadata',coalesce(new.metadata,'{}'::jsonb)
      ),
      'client_webhook:endpoint:'||v_endpoint.id::text||':event:'||new.id::text
    ) on conflict(dedupe_key) do nothing;
  end loop;
  return new;
end;
$$;
revoke all on function public.enqueue_client_webhooks_from_event() from public,anon,authenticated;
create trigger events_enqueue_client_webhooks after insert on public.events
for each row execute procedure public.enqueue_client_webhooks_from_event();

create or replace function public.list_webhook_endpoints(p_organization_id uuid)
returns table(id uuid,name text,url text,event_types text[],status text,signing_secret_prefix text,last_success_at timestamptz,last_failure_at timestamptz,last_error text,created_at timestamptz)
language sql stable security definer set search_path=public as $$
  select e.id,e.name,e.url,e.event_types,e.status,e.signing_secret_prefix,e.last_success_at,e.last_failure_at,e.last_error,e.created_at
  from public.webhook_endpoints e
  where e.organization_id=p_organization_id
    and public.has_org_role(p_organization_id,array['owner','admin'])
    and public.has_feature(p_organization_id,'outbound_webhooks')
  order by e.created_at desc;
$$;
revoke all on function public.list_webhook_endpoints(uuid) from public;
grant execute on function public.list_webhook_endpoints(uuid) to authenticated;

create or replace function public.list_webhook_deliveries(p_organization_id uuid,p_limit integer default 50)
returns table(id uuid,endpoint_id uuid,endpoint_name text,event_type text,status text,attempts integer,response_status integer,last_error text,delivered_at timestamptz,created_at timestamptz)
language sql stable security definer set search_path=public as $$
  select d.id,d.endpoint_id,e.name,d.event_type,d.status,d.attempts,d.response_status,d.last_error,d.delivered_at,d.created_at
  from public.webhook_deliveries d join public.webhook_endpoints e on e.id=d.endpoint_id
  where d.organization_id=p_organization_id
    and public.has_org_role(p_organization_id,array['owner','admin'])
    and public.has_feature(p_organization_id,'outbound_webhooks')
  order by d.created_at desc limit least(greatest(coalesce(p_limit,50),1),200);
$$;
revoke all on function public.list_webhook_deliveries(uuid,integer) from public;
grant execute on function public.list_webhook_deliveries(uuid,integer) to authenticated;
