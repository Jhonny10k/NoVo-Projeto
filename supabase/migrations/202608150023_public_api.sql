-- 2026-08-15 — API pública com chaves opacas, escopos e quota horária atômica.

update public.plans
set entitlements = coalesce(entitlements,'{}'::jsonb) || '{"public_api":false}'::jsonb,
    limits = '{"api_keys":3,"api_requests_per_hour":1000}'::jsonb || coalesce(limits,'{}'::jsonb)
where not coalesce(entitlements,'{}'::jsonb) ? 'public_api';

create table public.api_keys (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 100),
  key_prefix text not null check (char_length(key_prefix) between 8 and 32),
  secret_hash text not null unique check (char_length(secret_hash) = 64),
  scopes text[] not null default '{}'::text[] check (cardinality(scopes) between 1 and 20),
  status text not null default 'active' check (status in ('active','revoked')),
  expires_at timestamptz,
  last_used_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index api_keys_org_created_idx on public.api_keys(organization_id,created_at desc);
create index api_keys_org_status_idx on public.api_keys(organization_id,status);
create trigger api_keys_set_updated_at before update on public.api_keys
for each row execute procedure public.set_updated_at();
alter table public.api_keys enable row level security;
-- Sem policies: o hash da chave nunca fica disponível via PostgREST do tenant.

create table public.api_usage_windows (
  api_key_id uuid not null references public.api_keys(id) on delete cascade,
  window_start timestamptz not null,
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key(api_key_id,window_start)
);
alter table public.api_usage_windows enable row level security;
-- Infraestrutura server-only, sem policies.

create table public.api_request_logs (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  api_key_id uuid references public.api_keys(id) on delete set null,
  scope text not null,
  method text not null,
  route text not null check (char_length(route) between 1 and 240),
  response_status integer not null check (response_status between 100 and 599),
  duration_ms integer check (duration_ms is null or duration_ms >= 0),
  request_id text,
  created_at timestamptz not null default now()
);
create index api_request_logs_org_created_idx on public.api_request_logs(organization_id,created_at desc);
create index api_request_logs_key_created_idx on public.api_request_logs(api_key_id,created_at desc);
alter table public.api_request_logs enable row level security;
-- Logs de API são server-only; o tenant recebe somente agregados por RPC segura.

create or replace function public.service_organization_has_feature(p_organization_id uuid,p_feature text)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1
    from public.subscriptions s
    join public.plans p on p.id=s.plan_id and p.active=true
    join public.organizations o on o.id=s.organization_id and o.status='active'
    where s.organization_id=p_organization_id
      and coalesce((p.entitlements->>p_feature)::boolean,false)=true
      and (s.status='active' or (s.status='trial' and (s.trial_ends_at is null or s.trial_ends_at>now())))
  );
$$;
revoke all on function public.service_organization_has_feature(uuid,text) from public,anon,authenticated;

create or replace function public.service_plan_limit(p_organization_id uuid,p_limit text,p_default integer default null)
returns integer
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_limit integer;
begin
  select case when jsonb_typeof(p.limits->p_limit)='number' then (p.limits->>p_limit)::integer else p_default end
  into v_limit
  from public.subscriptions s
  join public.plans p on p.id=s.plan_id and p.active=true
  join public.organizations o on o.id=s.organization_id and o.status='active'
  where s.organization_id=p_organization_id
    and (s.status='active' or (s.status='trial' and (s.trial_ends_at is null or s.trial_ends_at>now())))
  order by (s.status='active') desc,s.created_at desc
  limit 1;
  return coalesce(v_limit,p_default);
end;
$$;
revoke all on function public.service_plan_limit(uuid,text,integer) from public,anon,authenticated;

create or replace function public.service_consume_public_api_key(
  p_secret_hash text,
  p_required_scope text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_key public.api_keys%rowtype;
  v_limit integer;
  v_window timestamptz:=date_trunc('hour',now());
  v_count integer;
begin
  if p_secret_hash !~ '^[0-9a-f]{64}$' or char_length(trim(coalesce(p_required_scope,'')))<3 then
    raise exception 'invalid api credentials';
  end if;

  select * into v_key from public.api_keys where secret_hash=p_secret_hash for update;
  if v_key.id is null or v_key.status<>'active' or (v_key.expires_at is not null and v_key.expires_at<=now()) then
    raise exception 'invalid api key';
  end if;
  if not public.service_organization_has_feature(v_key.organization_id,'public_api') then
    raise exception 'api feature unavailable';
  end if;
  if not ('*'=any(v_key.scopes) or p_required_scope=any(v_key.scopes)) then
    raise exception 'insufficient scope';
  end if;

  v_limit:=greatest(coalesce(public.service_plan_limit(v_key.organization_id,'api_requests_per_hour',1000),1000),1);
  insert into public.api_usage_windows(api_key_id,window_start,request_count)
  values(v_key.id,v_window,1)
  on conflict(api_key_id,window_start) do update
    set request_count=public.api_usage_windows.request_count+1,updated_at=now()
    where public.api_usage_windows.request_count < v_limit
  returning request_count into v_count;

  if v_count is null then raise exception 'api rate limit exceeded'; end if;
  update public.api_keys set last_used_at=now() where id=v_key.id;

  return jsonb_build_object(
    'organization_id',v_key.organization_id,
    'api_key_id',v_key.id,
    'key_prefix',v_key.key_prefix,
    'scopes',to_jsonb(v_key.scopes),
    'limit',v_limit,
    'remaining',greatest(v_limit-v_count,0),
    'reset_at',v_window+interval '1 hour'
  );
end;
$$;
revoke all on function public.service_consume_public_api_key(text,text) from public,anon,authenticated;
grant execute on function public.service_consume_public_api_key(text,text) to service_role;

create or replace function public.service_create_api_lead(
  p_organization_id uuid,p_name text,p_phone text default null,p_whatsapp text default null,p_email text default null,
  p_company text default null,p_interest text default null,p_potential_value_cents bigint default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_pipeline uuid;v_stage uuid;v_id uuid;v_email text;
begin
  if not public.service_organization_has_feature(p_organization_id,'public_api') then raise exception 'api feature unavailable'; end if;
  if char_length(trim(coalesce(p_name,''))) not between 2 and 160 then raise exception 'invalid name'; end if;
  v_email:=nullif(lower(trim(coalesce(p_email,''))),'');
  if v_email is not null and (char_length(v_email)>254 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') then raise exception 'invalid email'; end if;
  if p_potential_value_cents is not null and p_potential_value_cents<0 then raise exception 'invalid value'; end if;

  select id into v_pipeline from public.pipelines where organization_id=p_organization_id and is_default=true order by created_at limit 1;
  select id into v_stage from public.pipeline_stages where organization_id=p_organization_id and pipeline_id=v_pipeline and stage_key='new' limit 1;
  insert into public.leads(organization_id,pipeline_id,stage_id,name,phone,whatsapp,email,company,source,status,interest,potential_value_cents)
  values(p_organization_id,v_pipeline,v_stage,trim(p_name),nullif(left(trim(coalesce(p_phone,'')),40),''),nullif(left(trim(coalesce(p_whatsapp,'')),40),''),v_email,
    nullif(left(trim(coalesce(p_company,'')),160),''),'api','new',nullif(left(trim(coalesce(p_interest,'')),500),''),p_potential_value_cents)
  returning id into v_id;
  insert into public.events(organization_id,entity_type,entity_id,event_type,metadata)
  values(p_organization_id,'lead',v_id,'lead_created',jsonb_build_object('source','api'));
  return v_id;
end;
$$;
revoke all on function public.service_create_api_lead(uuid,text,text,text,text,text,text,bigint) from public,anon,authenticated;
grant execute on function public.service_create_api_lead(uuid,text,text,text,text,text,text,bigint) to service_role;

create or replace function public.list_api_keys(p_organization_id uuid)
returns table(id uuid,name text,key_prefix text,scopes text[],status text,expires_at timestamptz,last_used_at timestamptz,created_at timestamptz)
language sql
stable
security definer
set search_path=public
as $$
  select k.id,k.name,k.key_prefix,k.scopes,k.status,k.expires_at,k.last_used_at,k.created_at
  from public.api_keys k
  where k.organization_id=p_organization_id
    and public.has_org_role(p_organization_id,array['owner','admin'])
    and public.has_feature(p_organization_id,'public_api')
  order by k.created_at desc;
$$;
revoke all on function public.list_api_keys(uuid) from public;
grant execute on function public.list_api_keys(uuid) to authenticated;

create or replace function public.api_usage_summary(p_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select case when public.has_org_role(p_organization_id,array['owner','admin']) and public.has_feature(p_organization_id,'public_api') then
    jsonb_build_object(
      'last_24h',(select count(*) from public.api_request_logs l where l.organization_id=p_organization_id and l.created_at>=now()-interval '24 hours'),
      'errors_24h',(select count(*) from public.api_request_logs l where l.organization_id=p_organization_id and l.created_at>=now()-interval '24 hours' and l.response_status>=400),
      'active_keys',(select count(*) from public.api_keys k where k.organization_id=p_organization_id and k.status='active' and (k.expires_at is null or k.expires_at>now()))
    ) else null end;
$$;
revoke all on function public.api_usage_summary(uuid) from public;
grant execute on function public.api_usage_summary(uuid) to authenticated;

create or replace function public.admin_update_plan_limits(p_plan_id uuid,p_limits jsonb)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_platform_admin() then raise exception 'forbidden'; end if;
  if jsonb_typeof(p_limits)<>'object' or exists(select 1 from jsonb_each(p_limits) e where jsonb_typeof(e.value)<>'number') then raise exception 'invalid limits'; end if;
  if exists(select 1 from jsonb_each_text(p_limits) e where e.value::numeric<0 or e.value::numeric>100000000) then raise exception 'invalid limits'; end if;
  update public.plans set limits=coalesce(limits,'{}'::jsonb)||p_limits,updated_at=now() where id=p_plan_id;
  if not found then raise exception 'plan not found'; end if;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'platform.plan_limits_updated','plan',p_plan_id,p_limits);
end;
$$;
revoke all on function public.admin_update_plan_limits(uuid,jsonb) from public;
grant execute on function public.admin_update_plan_limits(uuid,jsonb) to authenticated;
