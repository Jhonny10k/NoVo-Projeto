-- 2026-08-15 — Dashboard Hoje com timezone da organização e comparação real de períodos.
alter table public.organizations add column if not exists timezone text not null default 'America/Sao_Paulo';

create or replace function public.organization_dashboard_summary(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz text;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_month_start timestamptz;
  v_previous_month_start timestamptz;
  v_crm boolean;
  v_quotes boolean;
  v_tasks boolean;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) then raise exception 'forbidden'; end if;
  select timezone into v_tz from public.organizations where id=p_organization_id;
  if v_tz is null then v_tz := 'America/Sao_Paulo'; end if;

  v_day_start := (date_trunc('day', now() at time zone v_tz) at time zone v_tz);
  v_day_end := v_day_start + interval '1 day';
  v_month_start := (date_trunc('month', now() at time zone v_tz) at time zone v_tz);
  v_previous_month_start := v_month_start - interval '1 month';
  v_crm := public.has_feature(p_organization_id,'crm');
  v_quotes := public.has_feature(p_organization_id,'quotes');
  v_tasks := public.has_feature(p_organization_id,'tasks');

  return jsonb_build_object(
    'timezone',v_tz,
    'leads_today',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_day_start and created_at<v_day_end),
    'leads_month',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_month_start),
    'leads_previous_month',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_previous_month_start and created_at<v_month_start),
    'leads_total',(select count(*) from public.leads where organization_id=p_organization_id),
    'potential_value_cents',coalesce((select sum(potential_value_cents) from public.leads where organization_id=p_organization_id and status not in ('won','lost')),0),
    'customers_total',case when v_crm then (select count(*) from public.customers where organization_id=p_organization_id) else null end,
    'followups_due',case when v_crm then (select count(*) from public.leads where organization_id=p_organization_id and next_contact_at is not null and next_contact_at<v_day_end and status not in ('won','lost')) else null end,
    'quotes_pending',case when v_quotes then (select count(*) from public.quotes where organization_id=p_organization_id and status in ('draft','sent','viewed','change_requested')) else null end,
    'quotes_month',case when v_quotes then (select count(*) from public.quotes where organization_id=p_organization_id and created_at>=v_month_start) else null end,
    'tasks_open',case when v_tasks then (select count(*) from public.tasks where organization_id=p_organization_id and status in ('open','in_progress')) else null end,
    'tasks_overdue',case when v_tasks then (select count(*) from public.tasks where organization_id=p_organization_id and status in ('open','in_progress') and due_at is not null and due_at<now()) else null end
  );
end;
$$;
revoke all on function public.organization_dashboard_summary(uuid) from public;
grant execute on function public.organization_dashboard_summary(uuid) to authenticated;

create or replace function public.schedule_lead_followup(p_organization_id uuid, p_lead_id uuid, p_local_datetime text)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tz text;
  v_when timestamptz;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin','sales','support']) or not public.has_feature(p_organization_id,'crm') then raise exception 'forbidden'; end if;
  select timezone into v_tz from public.organizations where id=p_organization_id;
  if v_tz is null then v_tz := 'America/Sao_Paulo'; end if;
  begin
    v_when := (p_local_datetime::timestamp at time zone v_tz);
  exception when others then raise exception 'invalid datetime'; end;
  if v_when < now() - interval '5 minutes' or v_when > now() + interval '2 years' then raise exception 'invalid datetime'; end if;
  update public.leads set next_contact_at=v_when, updated_at=now() where organization_id=p_organization_id and id=p_lead_id;
  if not found then raise exception 'lead not found'; end if;
  insert into public.events(organization_id,actor_user_id,entity_type,entity_id,event_type,metadata)
  values(p_organization_id,auth.uid(),'lead',p_lead_id,'note_added',jsonb_build_object('type','follow_up_scheduled','next_contact_at',v_when,'timezone',v_tz));
  return v_when;
end;
$$;
revoke all on function public.schedule_lead_followup(uuid,uuid,text) from public;
grant execute on function public.schedule_lead_followup(uuid,uuid,text) to authenticated;
