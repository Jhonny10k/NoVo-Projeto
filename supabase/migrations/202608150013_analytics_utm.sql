-- 2026-08-15 — Analytics próprio, UTM e relatórios baseados apenas em dados reais.

alter table public.leads
  add column if not exists utm_source text,
  add column if not exists utm_medium text,
  add column if not exists utm_campaign text,
  add column if not exists utm_content text,
  add column if not exists utm_term text;

create table public.site_visits (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  visitor_hash text not null check (char_length(visitor_hash) between 32 and 128),
  pathname text not null default '/',
  referrer_host text,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  utm_content text,
  utm_term text,
  created_at timestamptz not null default now()
);

create index site_visits_org_created_idx on public.site_visits(organization_id, created_at desc);
create index site_visits_org_visitor_idx on public.site_visits(organization_id, visitor_hash, created_at desc);

alter table public.site_visits enable row level security;
create policy site_visits_select_analytics on public.site_visits
for select to authenticated
using (public.is_org_member(organization_id) and public.has_feature(organization_id,'analytics'));
-- Sem policy de INSERT: visitas entram apenas pela RPC server-side/service role.

create or replace function public.record_site_visit(
  p_slug text,
  p_visitor_hash text,
  p_pathname text,
  p_referrer_host text,
  p_utm_source text,
  p_utm_medium text,
  p_utm_campaign text,
  p_utm_content text,
  p_utm_term text
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare v_org uuid;
begin
  if char_length(trim(coalesce(p_visitor_hash,''))) not between 32 and 128 then return false; end if;
  select o.id into v_org
  from public.organizations o
  join public.site_configs sc on sc.organization_id=o.id and sc.status='published'
  where o.slug=trim(p_slug) and o.status='active'
    and public.organization_has_entitlement(o.id,'analytics')
  limit 1;
  if v_org is null then return false; end if;

  -- Deduplica a mesma página/visitante por 30 minutos. Não armazena IP nem user-agent brutos.
  if exists(
    select 1 from public.site_visits sv
    where sv.organization_id=v_org
      and sv.visitor_hash=p_visitor_hash
      and sv.pathname=left(coalesce(nullif(trim(p_pathname),''),'/'),300)
      and sv.created_at>now()-interval '30 minutes'
  ) then return true; end if;

  insert into public.site_visits(
    organization_id,visitor_hash,pathname,referrer_host,
    utm_source,utm_medium,utm_campaign,utm_content,utm_term
  ) values (
    v_org,p_visitor_hash,left(coalesce(nullif(trim(p_pathname),''),'/'),300),nullif(left(trim(coalesce(p_referrer_host,'')),200),''),
    nullif(left(trim(coalesce(p_utm_source,'')),120),''),nullif(left(trim(coalesce(p_utm_medium,'')),120),''),
    nullif(left(trim(coalesce(p_utm_campaign,'')),160),''),nullif(left(trim(coalesce(p_utm_content,'')),160),''),
    nullif(left(trim(coalesce(p_utm_term,'')),160),'')
  );
  return true;
end; $$;
revoke all on function public.record_site_visit(text,text,text,text,text,text,text,text,text) from public;
revoke all on function public.record_site_visit(text,text,text,text,text,text,text,text,text) from anon;
revoke all on function public.record_site_visit(text,text,text,text,text,text,text,text,text) from authenticated;
grant execute on function public.record_site_visit(text,text,text,text,text,text,text,text,text) to service_role;

-- Overload do formulário público para associar UTM ao lead sem quebrar clientes antigos da RPC de 6 argumentos.
create or replace function public.public_create_quote_request(
  p_organization_slug text,
  p_name text,
  p_whatsapp text,
  p_email text,
  p_description text,
  p_honeypot text,
  p_utm_source text,
  p_utm_medium text,
  p_utm_campaign text,
  p_utm_content text,
  p_utm_term text
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_request uuid; v_lead uuid;
begin
  v_request:=public.public_create_quote_request(
    p_organization_slug,p_name,p_whatsapp,p_email,p_description,p_honeypot
  );
  select qr.lead_id into v_lead from public.quote_requests qr where qr.id=v_request;
  if v_lead is not null then
    update public.leads set
      utm_source=coalesce(nullif(left(trim(coalesce(p_utm_source,'')),120),''),utm_source),
      utm_medium=coalesce(nullif(left(trim(coalesce(p_utm_medium,'')),120),''),utm_medium),
      utm_campaign=coalesce(nullif(left(trim(coalesce(p_utm_campaign,'')),160),''),utm_campaign),
      utm_content=coalesce(nullif(left(trim(coalesce(p_utm_content,'')),160),''),utm_content),
      utm_term=coalesce(nullif(left(trim(coalesce(p_utm_term,'')),160),''),utm_term),
      updated_at=now()
    where id=v_lead;
  end if;
  return v_request;
end; $$;
revoke all on function public.public_create_quote_request(text,text,text,text,text,text,text,text,text,text,text) from public;
grant execute on function public.public_create_quote_request(text,text,text,text,text,text,text,text,text,text,text) to anon,authenticated;

create or replace function public.organization_analytics_summary(p_organization_id uuid,p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_days integer:=least(greatest(coalesce(p_days,30),7),365);
  v_since timestamptz;
  v_previous_since timestamptz;
  v_tz text;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) or not public.has_feature(p_organization_id,'analytics') then raise exception 'forbidden'; end if;
  select coalesce(timezone,'America/Sao_Paulo') into v_tz from public.organizations where id=p_organization_id;
  v_since:=now()-make_interval(days=>v_days);
  v_previous_since:=v_since-make_interval(days=>v_days);

  select jsonb_build_object(
    'days',v_days,
    'timezone',v_tz,
    'visitors',(select count(distinct visitor_hash) from public.site_visits where organization_id=p_organization_id and created_at>=v_since),
    'page_views',(select count(*) from public.site_visits where organization_id=p_organization_id and created_at>=v_since),
    'leads',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_since),
    'site_leads',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_since and source='site'),
    'previous_leads',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_previous_since and created_at<v_since),
    'customers',(select count(*) from public.customers where organization_id=p_organization_id and created_at>=v_since),
    'quotes',(select count(*) from public.quotes where organization_id=p_organization_id and created_at>=v_since),
    'approved_quotes',(select count(*) from public.quotes where organization_id=p_organization_id and status='approved' and coalesce(accepted_at,updated_at)>=v_since),
    'sales_cents',coalesce((select sum(total_cents) from public.quotes where organization_id=p_organization_id and status='approved' and coalesce(accepted_at,updated_at)>=v_since),0),
    'previous_sales_cents',coalesce((select sum(total_cents) from public.quotes where organization_id=p_organization_id and status='approved' and coalesce(accepted_at,updated_at)>=v_previous_since and coalesce(accepted_at,updated_at)<v_since),0),
    'average_ticket_cents',coalesce((select round(avg(total_cents))::bigint from public.quotes where organization_id=p_organization_id and status='approved' and coalesce(accepted_at,updated_at)>=v_since),0),
    'appointments',case when public.has_feature(p_organization_id,'appointments') then (select count(*) from public.appointments where organization_id=p_organization_id and created_at>=v_since) else null end,
    'lead_sources',coalesce((select jsonb_agg(jsonb_build_object('label',source,'count',qty) order by qty desc,label) from (select coalesce(nullif(source,''),'Sem origem') label,count(*) qty from public.leads where organization_id=p_organization_id and created_at>=v_since group by 1 order by 2 desc limit 12) s),'[]'::jsonb),
    'utm_sources',coalesce((select jsonb_agg(jsonb_build_object('label',label,'count',qty) order by qty desc,label) from (select coalesce(nullif(utm_source,''),'Sem UTM') label,count(*) qty from public.leads where organization_id=p_organization_id and created_at>=v_since group by 1 order by 2 desc limit 12) s),'[]'::jsonb),
    'utm_mediums',coalesce((select jsonb_agg(jsonb_build_object('label',label,'count',qty) order by qty desc,label) from (select coalesce(nullif(utm_medium,''),'Sem canal') label,count(*) qty from public.leads where organization_id=p_organization_id and created_at>=v_since group by 1 order by 2 desc limit 12) s),'[]'::jsonb),
    'top_items',coalesce((select jsonb_agg(jsonb_build_object('type',item_type,'description',description,'quantity',quantity,'revenue_cents',revenue_cents) order by revenue_cents desc) from (select qi.item_type,left(qi.description,120) description,sum(qi.quantity) quantity,sum(qi.total_cents) revenue_cents from public.quote_items qi join public.quotes q on q.id=qi.quote_id and q.organization_id=qi.organization_id where qi.organization_id=p_organization_id and q.status='approved' and coalesce(q.accepted_at,q.updated_at)>=v_since group by qi.item_type,left(qi.description,120) order by 4 desc limit 10) i),'[]'::jsonb),
    'daily',coalesce((select jsonb_agg(jsonb_build_object('date',d.day_value,'visits',d.visits,'leads',d.leads,'quotes',d.quotes,'sales_cents',d.sales_cents) order by d.day_value) from (
      select g::date as day_value,
        (select count(*) from public.site_visits sv where sv.organization_id=p_organization_id and (sv.created_at at time zone v_tz)::date=g::date) visits,
        (select count(*) from public.leads l where l.organization_id=p_organization_id and (l.created_at at time zone v_tz)::date=g::date) leads,
        (select count(*) from public.quotes q where q.organization_id=p_organization_id and (q.created_at at time zone v_tz)::date=g::date) quotes,
        coalesce((select sum(q.total_cents) from public.quotes q where q.organization_id=p_organization_id and q.status='approved' and (coalesce(q.accepted_at,q.updated_at) at time zone v_tz)::date=g::date),0) sales_cents
      from generate_series((now() at time zone v_tz)::date-(v_days-1),(now() at time zone v_tz)::date,interval '1 day') g
    ) d),'[]'::jsonb)
  ) into v_result;
  return v_result;
end; $$;
revoke all on function public.organization_analytics_summary(uuid,integer) from public;
grant execute on function public.organization_analytics_summary(uuid,integer) to authenticated;
