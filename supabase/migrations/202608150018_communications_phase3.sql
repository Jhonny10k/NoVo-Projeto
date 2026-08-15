-- 2026-08-15 — Fase 3 inicial: e-mail transacional e WhatsApp Cloud API oficial.
-- Segredos de WhatsApp ficam em tabela sem policy e são gravados somente pelo backend service-role.

update public.plans
set entitlements = coalesce(entitlements,'{}'::jsonb) || '{"email_transactional":true,"whatsapp_official":true}'::jsonb
where code in ('professional','ai');

create table public.integration_connections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider text not null check (provider in ('whatsapp_cloud')),
  status text not null default 'configured' check (status in ('disconnected','configured','active','error')),
  config jsonb not null default '{}'::jsonb check (jsonb_typeof(config)='object'),
  last_verified_at timestamptz,
  last_error text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,provider)
);
create trigger integration_connections_set_updated_at before update on public.integration_connections for each row execute procedure public.set_updated_at();
create index integration_connections_whatsapp_phone_idx on public.integration_connections ((config->>'phone_number_id')) where provider='whatsapp_cloud';
alter table public.integration_connections enable row level security;
create policy integration_connections_select_member on public.integration_connections for select to authenticated
using (public.is_org_member(organization_id));
-- Escrita somente pelo backend após validar papel/entitlement na Server Action.

create table public.integration_secrets (
  connection_id uuid primary key references public.integration_connections(id) on delete cascade,
  ciphertext text not null,
  iv text not null,
  auth_tag text not null,
  updated_at timestamptz not null default now()
);
alter table public.integration_secrets enable row level security;
-- Sem policies: segredos nunca são retornados para anon/authenticated.

create table public.communication_messages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  channel text not null check (channel in ('email','whatsapp')),
  direction text not null check (direction in ('inbound','outbound')),
  provider text not null check (provider in ('resend','whatsapp_cloud')),
  provider_message_id text,
  lead_id uuid references public.leads(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  sender text,
  recipient text,
  subject text,
  body text check (body is null or char_length(body)<=10000),
  message_type text,
  template_name text,
  status text not null check (status in ('queued','sent','delivered','read','failed','received')),
  error_code text,
  error_message text,
  created_by uuid references auth.users(id) on delete set null,
  sent_at timestamptz,
  delivered_at timestamptz,
  read_at timestamptz,
  received_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index communication_messages_provider_id_uidx on public.communication_messages(provider,provider_message_id) where provider_message_id is not null;
create index communication_messages_org_created_idx on public.communication_messages(organization_id,created_at desc);
create index communication_messages_lead_idx on public.communication_messages(organization_id,lead_id,created_at desc) where lead_id is not null;
create index communication_messages_customer_idx on public.communication_messages(organization_id,customer_id,created_at desc) where customer_id is not null;
create trigger communication_messages_set_updated_at before update on public.communication_messages for each row execute procedure public.set_updated_at();
alter table public.communication_messages enable row level security;
create policy communication_messages_select_member on public.communication_messages for select to authenticated
using (public.is_org_member(organization_id));
-- INSERT/UPDATE externos ficam restritos ao backend service-role.

-- Resolve conexão sem expor segredo; usado pelo Webhook assinado da Meta.
create or replace function public.service_find_whatsapp_connection(p_phone_number_id text)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select jsonb_build_object('id',c.id,'organization_id',c.organization_id,'status',c.status,'config',c.config)
  from public.integration_connections c
  where c.provider='whatsapp_cloud' and c.status='active' and c.config->>'phone_number_id'=trim(p_phone_number_id)
  limit 1;
$$;
revoke all on function public.service_find_whatsapp_connection(text) from public, anon, authenticated;
grant execute on function public.service_find_whatsapp_connection(text) to service_role;

-- Registra mensagem recebida de forma transacional, reaproveitando lead/cliente pelo telefone.
create or replace function public.service_record_whatsapp_inbound(
  p_phone_number_id text,
  p_provider_message_id text,
  p_from_phone text,
  p_contact_name text,
  p_body text,
  p_message_type text,
  p_received_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_conn public.integration_connections%rowtype; v_org uuid; v_phone text; v_lead uuid; v_customer uuid; v_message uuid; v_pipeline uuid; v_stage uuid; v_inserted boolean:=false;
begin
  select * into v_conn from public.integration_connections
  where provider='whatsapp_cloud' and status='active' and config->>'phone_number_id'=trim(p_phone_number_id) limit 1;
  if v_conn.id is null then raise exception 'whatsapp connection not found'; end if;
  v_org:=v_conn.organization_id;
  v_phone:=regexp_replace(coalesce(p_from_phone,''),'[^0-9]','','g');
  if char_length(v_phone) not between 8 and 15 then raise exception 'invalid sender phone'; end if;
  if char_length(trim(coalesce(p_provider_message_id,'')))<3 then raise exception 'invalid provider message id'; end if;

  select l.id into v_lead from public.leads l
  where l.organization_id=v_org and (
    regexp_replace(coalesce(l.whatsapp,''),'[^0-9]','','g')=v_phone or regexp_replace(coalesce(l.phone,''),'[^0-9]','','g')=v_phone
  ) order by l.updated_at desc limit 1;
  select c.id into v_customer from public.customers c
  where c.organization_id=v_org and (
    regexp_replace(coalesce(c.whatsapp,''),'[^0-9]','','g')=v_phone or regexp_replace(coalesce(c.phone,''),'[^0-9]','','g')=v_phone
  ) order by c.updated_at desc limit 1;

  if v_lead is null and v_customer is null then
    select p.id into v_pipeline from public.pipelines p where p.organization_id=v_org and p.is_default=true order by p.created_at limit 1;
    if v_pipeline is not null then select ps.id into v_stage from public.pipeline_stages ps where ps.pipeline_id=v_pipeline order by ps.sort_order limit 1; end if;
    insert into public.leads(organization_id,pipeline_id,stage_id,name,whatsapp,source,status,last_contact_at)
    values(v_org,v_pipeline,v_stage,left(coalesce(nullif(trim(p_contact_name),''),v_phone),160),v_phone,'whatsapp','new',coalesce(p_received_at,now())) returning id into v_lead;
  end if;

  insert into public.communication_messages(
    organization_id,channel,direction,provider,provider_message_id,lead_id,customer_id,sender,body,message_type,status,received_at
  ) values(
    v_org,'whatsapp','inbound','whatsapp_cloud',trim(p_provider_message_id),v_lead,v_customer,v_phone,left(p_body,10000),left(coalesce(p_message_type,'unknown'),50),'received',coalesce(p_received_at,now())
  ) on conflict (provider,provider_message_id) where provider_message_id is not null do nothing
  returning id into v_message;

  if v_message is not null then
    v_inserted:=true;
    if v_lead is not null then
      update public.leads set last_contact_at=coalesce(p_received_at,now()),updated_at=now() where id=v_lead and organization_id=v_org;
      insert into public.events(organization_id,entity_type,entity_id,event_type,metadata)
      values(v_org,'lead',v_lead,'whatsapp_message_received',jsonb_build_object('message_id',v_message,'message_type',coalesce(p_message_type,'unknown')));
    elsif v_customer is not null then
      insert into public.events(organization_id,entity_type,entity_id,event_type,metadata)
      values(v_org,'customer',v_customer,'whatsapp_message_received',jsonb_build_object('message_id',v_message,'message_type',coalesce(p_message_type,'unknown')));
    end if;
  else
    select id into v_message from public.communication_messages where provider='whatsapp_cloud' and provider_message_id=trim(p_provider_message_id);
  end if;

  return jsonb_build_object('organization_id',v_org,'lead_id',v_lead,'customer_id',v_customer,'message_id',v_message,'inserted',v_inserted);
end; $$;
revoke all on function public.service_record_whatsapp_inbound(text,text,text,text,text,text,timestamptz) from public, anon, authenticated;
grant execute on function public.service_record_whatsapp_inbound(text,text,text,text,text,text,timestamptz) to service_role;

create or replace function public.service_update_communication_status(
  p_provider text,
  p_provider_message_id text,
  p_status text,
  p_error_code text,
  p_error_message text,
  p_at timestamptz
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if p_provider not in('resend','whatsapp_cloud') or p_status not in('sent','delivered','read','failed') then raise exception 'invalid provider status'; end if;
  update public.communication_messages set
    status=p_status,
    error_code=nullif(left(coalesce(p_error_code,''),100),''),
    error_message=nullif(left(coalesce(p_error_message,''),1000),''),
    sent_at=case when p_status='sent' then coalesce(p_at,now()) else sent_at end,
    delivered_at=case when p_status='delivered' then coalesce(p_at,now()) else delivered_at end,
    read_at=case when p_status='read' then coalesce(p_at,now()) else read_at end,
    updated_at=now()
  where provider=p_provider and provider_message_id=p_provider_message_id;
end; $$;
revoke all on function public.service_update_communication_status(text,text,text,text,text,timestamptz) from public, anon, authenticated;
grant execute on function public.service_update_communication_status(text,text,text,text,text,timestamptz) to service_role;
