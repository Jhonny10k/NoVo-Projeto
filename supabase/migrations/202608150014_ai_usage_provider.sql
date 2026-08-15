-- 2026-08-15 — IA desacoplada, consumo auditável e limites mensais.

update public.plans
set entitlements=coalesce(entitlements,'{}'::jsonb)||'{"ai_quotes":true}'::jsonb,
    limits=coalesce(limits,'{}'::jsonb)||'{"ai_requests_per_month":500,"ai_tokens_per_month":2000000}'::jsonb
where code='ai';

create table public.ai_usage (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  resource text not null check(resource in ('assistant','lead_response','copy','quote','insights')),
  status text not null default 'pending' check(status in ('pending','succeeded','failed')),
  provider text,
  model text,
  provider_request_id text,
  input_tokens integer not null default 0 check(input_tokens>=0),
  output_tokens integer not null default 0 check(output_tokens>=0),
  total_tokens integer not null default 0 check(total_tokens>=0),
  estimated_cost_usd_micros bigint check(estimated_cost_usd_micros is null or estimated_cost_usd_micros>=0),
  error_code text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
create index ai_usage_org_month_idx on public.ai_usage(organization_id,created_at desc);
create index ai_usage_user_month_idx on public.ai_usage(user_id,created_at desc);
alter table public.ai_usage enable row level security;
create policy ai_usage_select_member on public.ai_usage for select to authenticated
using(public.is_org_member(organization_id) and public.organization_has_entitlement(organization_id,'ai_assistant'));
-- Escrita somente pela RPC de reserva e pelo backend service-role após a chamada do provider.

create or replace function public.begin_ai_usage(p_organization_id uuid,p_resource text)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_feature text;
  v_tz text;
  v_month_start timestamptz;
  v_request_limit integer;
  v_token_limit integer;
  v_requests integer;
  v_tokens bigint;
  v_id uuid;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin','sales','support']) then raise exception 'forbidden'; end if;
  v_feature:=case p_resource
    when 'assistant' then 'ai_assistant'
    when 'lead_response' then 'ai_responses'
    when 'copy' then 'ai_copy'
    when 'quote' then 'ai_quotes'
    when 'insights' then 'ai_insights'
    else null end;
  if v_feature is null or not public.has_feature(p_organization_id,v_feature) then raise exception 'feature unavailable'; end if;
  -- Serializa reservas do mesmo tenant para evitar ultrapassar limites por concorrência.
  perform pg_advisory_xact_lock(hashtext(p_organization_id::text)::bigint);
  select coalesce(timezone,'America/Sao_Paulo') into v_tz from public.organizations where id=p_organization_id;
  v_month_start:=(date_trunc('month',now() at time zone v_tz) at time zone v_tz);
  v_request_limit:=coalesce(public.feature_limit(p_organization_id,'ai_requests_per_month'),500);
  v_token_limit:=coalesce(public.feature_limit(p_organization_id,'ai_tokens_per_month'),2000000);
  select count(*),coalesce(sum(total_tokens),0) into v_requests,v_tokens
  from public.ai_usage where organization_id=p_organization_id and created_at>=v_month_start;
  if v_request_limit<=0 or v_requests>=v_request_limit then raise exception 'ai request limit reached'; end if;
  if v_token_limit<=0 or v_tokens>=v_token_limit then raise exception 'ai token limit reached'; end if;
  insert into public.ai_usage(organization_id,user_id,resource) values(p_organization_id,auth.uid(),p_resource) returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.begin_ai_usage(uuid,text) from public;
grant execute on function public.begin_ai_usage(uuid,text) to authenticated;

create or replace function public.ai_usage_summary(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_tz text;v_month_start timestamptz;v_req integer;v_tok integer;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) or not public.organization_has_entitlement(p_organization_id,'ai_assistant') then raise exception 'forbidden';end if;
  select coalesce(timezone,'America/Sao_Paulo') into v_tz from public.organizations where id=p_organization_id;
  v_month_start:=(date_trunc('month',now() at time zone v_tz) at time zone v_tz);
  v_req:=coalesce(public.feature_limit(p_organization_id,'ai_requests_per_month'),500);v_tok:=coalesce(public.feature_limit(p_organization_id,'ai_tokens_per_month'),2000000);
  return jsonb_build_object(
    'request_limit',v_req,'token_limit',v_tok,
    'requests_used',(select count(*) from public.ai_usage where organization_id=p_organization_id and created_at>=v_month_start),
    'tokens_used',coalesce((select sum(total_tokens) from public.ai_usage where organization_id=p_organization_id and created_at>=v_month_start),0),
    'estimated_cost_usd_micros',coalesce((select sum(estimated_cost_usd_micros) from public.ai_usage where organization_id=p_organization_id and created_at>=v_month_start),0),
    'successful_requests',(select count(*) from public.ai_usage where organization_id=p_organization_id and created_at>=v_month_start and status='succeeded'),
    'failed_requests',(select count(*) from public.ai_usage where organization_id=p_organization_id and created_at>=v_month_start and status='failed')
  );
end; $$;
revoke all on function public.ai_usage_summary(uuid) from public;
grant execute on function public.ai_usage_summary(uuid) to authenticated;
