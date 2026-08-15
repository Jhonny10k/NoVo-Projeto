-- 2026-08-15 — Fase 2: agenda, disponibilidade e agendamento público seguro.
create extension if not exists btree_gist;

create table public.booking_settings (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  enabled boolean not null default false,
  slot_duration_minutes integer not null default 60 check (slot_duration_minutes between 15 and 480),
  buffer_minutes integer not null default 0 check (buffer_minutes between 0 and 180),
  availability jsonb not null default '{"1":[["08:00","18:00"]],"2":[["08:00","18:00"]],"3":[["08:00","18:00"]],"4":[["08:00","18:00"]],"5":[["08:00","18:00"]]}'::jsonb
    check (jsonb_typeof(availability)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger booking_settings_set_updated_at before update on public.booking_settings for each row execute procedure public.set_updated_at();

create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  service_id uuid references public.services(id) on delete set null,
  professional_user_id uuid references auth.users(id) on delete set null,
  contact_name text check (contact_name is null or char_length(contact_name) between 2 and 160),
  contact_phone text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'scheduled' check (status in ('scheduled','confirmed','completed','canceled','no_show')),
  source text not null default 'internal' check (source in ('internal','public')),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (ends_at <= starts_at + interval '12 hours')
);
create index appointments_org_start_idx on public.appointments(organization_id, starts_at, status);
create index appointments_professional_start_idx on public.appointments(professional_user_id, starts_at) where professional_user_id is not null;
create trigger appointments_set_updated_at before update on public.appointments for each row execute procedure public.set_updated_at();

alter table public.booking_settings enable row level security;
alter table public.appointments enable row level security;
create policy booking_settings_select_member on public.booking_settings for select to authenticated using (public.is_org_member(organization_id));
create policy booking_settings_insert_admin on public.booking_settings for insert to authenticated with check (public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'appointments'));
create policy booking_settings_update_admin on public.booking_settings for update to authenticated using (public.has_org_role(organization_id,array['owner','admin'])) with check (public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'appointments'));
create policy appointments_select_member on public.appointments for select to authenticated using (public.is_org_member(organization_id) and public.has_feature(organization_id,'appointments'));
-- Escrita de appointments é feita pelas RPCs abaixo para centralizar conflito, timezone e auditoria.

insert into public.booking_settings(organization_id)
select o.id from public.organizations o
where not exists(select 1 from public.booking_settings b where b.organization_id=o.id)
on conflict do nothing;

create or replace function public.save_booking_settings(
  p_organization_id uuid,
  p_enabled boolean,
  p_slot_duration_minutes integer,
  p_buffer_minutes integer,
  p_availability jsonb
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin']) or not public.has_feature(p_organization_id,'appointments') then raise exception 'forbidden'; end if;
  if p_slot_duration_minutes not between 15 and 480 or p_buffer_minutes not between 0 and 180 or jsonb_typeof(p_availability)<>'object' then raise exception 'invalid settings'; end if;
  insert into public.booking_settings(organization_id,enabled,slot_duration_minutes,buffer_minutes,availability)
  values(p_organization_id,p_enabled,p_slot_duration_minutes,p_buffer_minutes,p_availability)
  on conflict(organization_id) do update set enabled=excluded.enabled,slot_duration_minutes=excluded.slot_duration_minutes,buffer_minutes=excluded.buffer_minutes,availability=excluded.availability,updated_at=now();
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id)
  values(p_organization_id,auth.uid(),'booking.settings_updated','organization',p_organization_id);
end;
$$;
revoke all on function public.save_booking_settings(uuid,boolean,integer,integer,jsonb) from public;
grant execute on function public.save_booking_settings(uuid,boolean,integer,integer,jsonb) to authenticated;

create or replace function public.create_appointment(
  p_organization_id uuid,
  p_lead_id uuid,
  p_customer_id uuid,
  p_service_id uuid,
  p_professional_user_id uuid,
  p_local_start text,
  p_duration_minutes integer,
  p_notes text
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_tz text; v_start timestamptz; v_end timestamptz; v_duration integer; v_id uuid; v_buffer integer := 0;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin','sales','support']) or not public.has_feature(p_organization_id,'appointments') then raise exception 'forbidden'; end if;
  select timezone into v_tz from public.organizations where id=p_organization_id;
  if v_tz is null then v_tz:='America/Sao_Paulo'; end if;
  select coalesce(buffer_minutes,0) into v_buffer from public.booking_settings where organization_id=p_organization_id;
  v_buffer := coalesce(v_buffer,0);
  begin v_start := (p_local_start::timestamp at time zone v_tz); exception when others then raise exception 'invalid datetime'; end;
  if v_start < now()-interval '5 minutes' or v_start > now()+interval '2 years' then raise exception 'invalid datetime'; end if;
  if p_service_id is not null and not exists(select 1 from public.services where id=p_service_id and organization_id=p_organization_id and active=true) then raise exception 'service not found'; end if;
  if p_customer_id is not null and not exists(select 1 from public.customers where id=p_customer_id and organization_id=p_organization_id) then raise exception 'customer not found'; end if;
  if p_lead_id is not null and not exists(select 1 from public.leads where id=p_lead_id and organization_id=p_organization_id) then raise exception 'lead not found'; end if;
  if p_professional_user_id is not null and not exists(select 1 from public.organization_members where organization_id=p_organization_id and user_id=p_professional_user_id and status='active') then raise exception 'professional not found'; end if;
  v_duration := coalesce(nullif(p_duration_minutes,0),(select duration_minutes from public.services where id=p_service_id),60);
  if v_duration not between 15 and 480 then raise exception 'invalid duration'; end if;
  v_end := v_start + make_interval(mins=>v_duration);
  if p_professional_user_id is not null and exists(select 1 from public.appointments a where a.organization_id=p_organization_id and a.professional_user_id=p_professional_user_id and a.status in('scheduled','confirmed') and tstzrange(a.starts_at-make_interval(mins=>v_buffer),a.ends_at+make_interval(mins=>v_buffer),'[)') && tstzrange(v_start,v_end,'[)')) then raise exception 'schedule conflict'; end if;
  insert into public.appointments(organization_id,lead_id,customer_id,service_id,professional_user_id,starts_at,ends_at,notes,source,created_by)
  values(p_organization_id,p_lead_id,p_customer_id,p_service_id,p_professional_user_id,v_start,v_end,nullif(trim(coalesce(p_notes,'')),''),'internal',auth.uid()) returning id into v_id;
  insert into public.events(organization_id,actor_user_id,entity_type,entity_id,event_type,metadata)
  values(p_organization_id,auth.uid(),'appointment',v_id,'appointment_created',jsonb_build_object('starts_at',v_start,'ends_at',v_end,'source','internal'));
  return v_id;
end;
$$;
revoke all on function public.create_appointment(uuid,uuid,uuid,uuid,uuid,text,integer,text) from public;
grant execute on function public.create_appointment(uuid,uuid,uuid,uuid,uuid,text,integer,text) to authenticated;

create or replace function public.update_appointment_status(p_organization_id uuid,p_appointment_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin','sales','support']) or not public.has_feature(p_organization_id,'appointments') then raise exception 'forbidden'; end if;
  if p_status not in('scheduled','confirmed','completed','canceled','no_show') then raise exception 'invalid status'; end if;
  update public.appointments set status=p_status,updated_at=now() where id=p_appointment_id and organization_id=p_organization_id;
  if not found then raise exception 'appointment not found'; end if;
  insert into public.events(organization_id,actor_user_id,entity_type,entity_id,event_type,metadata)
  values(p_organization_id,auth.uid(),'appointment',p_appointment_id,'appointment_status_changed',jsonb_build_object('status',p_status));
end; $$;
revoke all on function public.update_appointment_status(uuid,uuid,text) from public;
grant execute on function public.update_appointment_status(uuid,uuid,text) to authenticated;

create or replace function public.get_public_booking(p_slug text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_org public.organizations%rowtype; v_settings public.booking_settings%rowtype;
begin
  select * into v_org from public.organizations where slug=p_slug and status='active' limit 1;
  if v_org.id is null or not public.organization_has_entitlement(v_org.id,'appointments') then return null; end if;
  select * into v_settings from public.booking_settings where organization_id=v_org.id and enabled=true;
  if v_settings.organization_id is null then return null; end if;
  return jsonb_build_object(
    'organization',jsonb_build_object('name',v_org.name,'slug',v_org.slug,'timezone',v_org.timezone,'city',v_org.city,'state',v_org.state),
    'settings',jsonb_build_object('slot_duration_minutes',v_settings.slot_duration_minutes,'buffer_minutes',v_settings.buffer_minutes,'availability',v_settings.availability),
    'services',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'duration_minutes',coalesce(s.duration_minutes,v_settings.slot_duration_minutes),'starting_price_cents',s.starting_price_cents) order by s.name) from public.services s where s.organization_id=v_org.id and s.active=true),'[]'::jsonb)
  );
end; $$;
revoke all on function public.get_public_booking(text) from public;
grant execute on function public.get_public_booking(text) to anon,authenticated;

create or replace function public.public_create_appointment(p_slug text,p_service_id uuid,p_local_start text,p_name text,p_phone text)
returns uuid language plpgsql security definer set search_path=public as $$
declare
  v_org public.organizations%rowtype; v_settings public.booking_settings%rowtype; v_service public.services%rowtype;
  v_start_local timestamp; v_end_local timestamp; v_start timestamptz; v_end timestamptz; v_day text; v_ranges jsonb; v_allowed boolean; v_phone text; v_lead uuid; v_pipeline uuid; v_stage uuid; v_id uuid;
begin
  select * into v_org from public.organizations where slug=p_slug and status='active' limit 1;
  if v_org.id is null or not public.organization_has_entitlement(v_org.id,'appointments') then raise exception 'booking unavailable'; end if;
  select * into v_settings from public.booking_settings where organization_id=v_org.id and enabled=true;
  if v_settings.organization_id is null then raise exception 'booking unavailable'; end if;
  select * into v_service from public.services where id=p_service_id and organization_id=v_org.id and active=true;
  if v_service.id is null then raise exception 'service unavailable'; end if;
  if char_length(trim(coalesce(p_name,'')))<2 then raise exception 'invalid name'; end if;
  v_phone:=regexp_replace(coalesce(p_phone,''),'\D','','g'); if char_length(v_phone)<8 then raise exception 'invalid phone'; end if;
  begin v_start_local:=p_local_start::timestamp; exception when others then raise exception 'invalid datetime'; end;
  v_end_local:=v_start_local+make_interval(mins=>coalesce(v_service.duration_minutes,v_settings.slot_duration_minutes));
  if v_end_local::date<>v_start_local::date then raise exception 'outside availability'; end if;
  v_start:=v_start_local at time zone v_org.timezone; v_end:=v_end_local at time zone v_org.timezone;
  if v_start<now()+interval '15 minutes' or v_start>now()+interval '180 days' then raise exception 'invalid datetime'; end if;
  v_day:=extract(isodow from v_start_local)::integer::text; v_ranges:=v_settings.availability->v_day;
  if v_ranges is null or jsonb_typeof(v_ranges)<>'array' then raise exception 'outside availability'; end if;
  select exists(select 1 from jsonb_array_elements(v_ranges) r where jsonb_typeof(r)='array' and jsonb_array_length(r)>=2 and (r->>0)::time<=v_start_local::time and (r->>1)::time>=v_end_local::time) into v_allowed;
  if not coalesce(v_allowed,false) then raise exception 'outside availability'; end if;
  if exists(select 1 from public.appointments a where a.organization_id=v_org.id and a.status in('scheduled','confirmed') and tstzrange(a.starts_at-make_interval(mins=>v_settings.buffer_minutes),a.ends_at+make_interval(mins=>v_settings.buffer_minutes),'[)') && tstzrange(v_start,v_end,'[)')) then raise exception 'schedule conflict'; end if;

  select id into v_lead from public.leads where organization_id=v_org.id and (regexp_replace(coalesce(phone,''),'\D','','g')=v_phone or regexp_replace(coalesce(whatsapp,''),'\D','','g')=v_phone) order by created_at desc limit 1;
  if v_lead is null then
    select id into v_pipeline from public.pipelines where organization_id=v_org.id and is_default=true limit 1;
    select id into v_stage from public.pipeline_stages where pipeline_id=v_pipeline and stage_key='new' limit 1;
    insert into public.leads(organization_id,pipeline_id,stage_id,name,phone,whatsapp,source,status,interest)
    values(v_org.id,v_pipeline,v_stage,trim(p_name),v_phone,v_phone,'booking','new',v_service.name) returning id into v_lead;
    insert into public.events(organization_id,entity_type,entity_id,event_type,metadata) values(v_org.id,'lead',v_lead,'lead_created',jsonb_build_object('source','booking'));
  end if;

  insert into public.appointments(organization_id,lead_id,service_id,contact_name,contact_phone,starts_at,ends_at,source)
  values(v_org.id,v_lead,v_service.id,trim(p_name),v_phone,v_start,v_end,'public') returning id into v_id;
  insert into public.events(organization_id,entity_type,entity_id,event_type,metadata)
  values(v_org.id,'appointment',v_id,'appointment_created',jsonb_build_object('starts_at',v_start,'ends_at',v_end,'source','public','service',v_service.name));
  return v_id;
end; $$;
revoke all on function public.public_create_appointment(text,uuid,text,text,text) from public;
grant execute on function public.public_create_appointment(text,uuid,text,text,text) to anon,authenticated;

-- Notificações também passam a cobrir a agenda.
create or replace function public.fanout_event_notification()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_title text; v_body text; v_kind text:='info'; v_pref_key text:='leads';
begin
  case new.event_type
    when 'quote_request_received' then v_title:='Novo pedido de orçamento'; v_body:='Um novo contato chegou pelo site e precisa de atendimento.'; v_pref_key:='leads';
    when 'quote_response' then
      v_pref_key:='quotes';
      if coalesce(new.metadata->>'status','')='approved' then v_title:='Orçamento aprovado';v_body:='O cliente aprovou um orçamento.';v_kind:='success';
      elsif coalesce(new.metadata->>'status','')='change_requested' then v_title:='Cliente pediu alteração';v_body:='Um orçamento recebeu uma solicitação de alteração.';v_kind:='warning';
      elsif coalesce(new.metadata->>'status','')='rejected' then v_title:='Orçamento recusado';v_body:='Um cliente recusou um orçamento.';v_kind:='warning'; else return new; end if;
    when 'lead_converted_to_customer' then v_title:='Novo cliente';v_body:='Um lead foi convertido em cliente.';v_kind:='success';v_pref_key:='leads';
    when 'subscription_status_changed' then v_title:='Assinatura atualizada';v_body:='O status da assinatura mudou para '||coalesce(new.metadata->>'status','desconhecido')||'.';v_kind:='billing';v_pref_key:='billing';
    when 'appointment_created' then v_title:='Novo agendamento';v_pref_key:='appointments';v_body:=case when coalesce(new.metadata->>'source','')='public' then 'Um cliente realizou um agendamento pelo site.' else 'Um novo compromisso foi adicionado à agenda.' end;
    when 'appointment_status_changed' then v_title:='Agendamento atualizado';v_pref_key:='appointments';v_body:='O status de um agendamento foi alterado para '||coalesce(new.metadata->>'status','desconhecido')||'.';
    else return new;
  end case;
  insert into public.notifications(organization_id,user_id,source_event_id,kind,title,body,entity_type,entity_id)
  select new.organization_id,m.user_id,new.id,v_kind,v_title,v_body,new.entity_type,new.entity_id from public.organization_members m
  left join public.profiles p on p.id=m.user_id
  where m.organization_id=new.organization_id and m.status='active'
    and coalesce(p.notification_preferences->>v_pref_key,'true')='true' and (new.actor_user_id is null or m.user_id<>new.actor_user_id)
  on conflict(source_event_id,user_id) do nothing;
  return new;
end; $$;
revoke all on function public.fanout_event_notification() from public;
revoke all on function public.fanout_event_notification() from anon;
revoke all on function public.fanout_event_notification() from authenticated;

-- Dashboard passa a incluir agenda somente quando o entitlement estiver ativo.
create or replace function public.organization_dashboard_summary(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_tz text; v_day_start timestamptz; v_day_end timestamptz; v_month_start timestamptz; v_previous_month_start timestamptz;
  v_crm boolean; v_quotes boolean; v_tasks boolean; v_appointments boolean;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) then raise exception 'forbidden'; end if;
  select timezone into v_tz from public.organizations where id=p_organization_id; if v_tz is null then v_tz:='America/Sao_Paulo'; end if;
  v_day_start:=(date_trunc('day',now() at time zone v_tz) at time zone v_tz); v_day_end:=v_day_start+interval '1 day';
  v_month_start:=(date_trunc('month',now() at time zone v_tz) at time zone v_tz); v_previous_month_start:=v_month_start-interval '1 month';
  v_crm:=public.has_feature(p_organization_id,'crm'); v_quotes:=public.has_feature(p_organization_id,'quotes'); v_tasks:=public.has_feature(p_organization_id,'tasks'); v_appointments:=public.has_feature(p_organization_id,'appointments');
  return jsonb_build_object(
    'timezone',v_tz,
    'leads_today',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_day_start and created_at<v_day_end),
    'leads_month',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_month_start),
    'leads_previous_month',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_previous_month_start and created_at<v_month_start),
    'leads_total',(select count(*) from public.leads where organization_id=p_organization_id),
    'potential_value_cents',coalesce((select sum(potential_value_cents) from public.leads where organization_id=p_organization_id and status not in('won','lost')),0),
    'customers_total',case when v_crm then(select count(*) from public.customers where organization_id=p_organization_id) else null end,
    'followups_due',case when v_crm then(select count(*) from public.leads where organization_id=p_organization_id and next_contact_at is not null and next_contact_at<v_day_end and status not in('won','lost')) else null end,
    'quotes_pending',case when v_quotes then(select count(*) from public.quotes where organization_id=p_organization_id and status in('draft','sent','viewed','change_requested')) else null end,
    'quotes_month',case when v_quotes then(select count(*) from public.quotes where organization_id=p_organization_id and created_at>=v_month_start) else null end,
    'tasks_open',case when v_tasks then(select count(*) from public.tasks where organization_id=p_organization_id and status in('open','in_progress')) else null end,
    'tasks_overdue',case when v_tasks then(select count(*) from public.tasks where organization_id=p_organization_id and status in('open','in_progress') and due_at is not null and due_at<now()) else null end,
    'appointments_today',case when v_appointments then(select count(*) from public.appointments where organization_id=p_organization_id and status in('scheduled','confirmed') and starts_at>=v_day_start and starts_at<v_day_end) else null end
  );
end; $$;
revoke all on function public.organization_dashboard_summary(uuid) from public;
grant execute on function public.organization_dashboard_summary(uuid) to authenticated;
