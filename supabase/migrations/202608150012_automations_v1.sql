-- 2026-08-15 — Fase 2: motor de automações event-driven com ações internas seguras.

update public.plans
set entitlements = coalesce(entitlements,'{}'::jsonb) || '{"automations":true}'::jsonb
where code in ('professional','ai');

create table public.automations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 160),
  trigger_event text not null check (trigger_event in ('lead_created','quote_created','quote_link_enabled','quote_viewed','quote_response','appointment_created','appointment_status_changed')),
  conditions jsonb not null default '{}'::jsonb check (jsonb_typeof(conditions)='object'),
  actions jsonb not null check (jsonb_typeof(actions)='array' and jsonb_array_length(actions) between 1 and 10),
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index automations_org_trigger_idx on public.automations(organization_id,trigger_event,active);
create trigger automations_set_updated_at before update on public.automations for each row execute procedure public.set_updated_at();

create table public.automation_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  automation_id uuid not null references public.automations(id) on delete cascade,
  source_event_id uuid references public.events(id) on delete set null,
  status text not null check (status in ('executed','failed','ignored','dry_run')),
  reason text,
  actions_log jsonb not null default '[]'::jsonb check (jsonb_typeof(actions_log)='array'),
  created_at timestamptz not null default now(),
  unique(automation_id,source_event_id)
);
create index automation_runs_org_created_idx on public.automation_runs(organization_id,created_at desc);

alter table public.automations enable row level security;
alter table public.automation_runs enable row level security;
create policy automations_select_member on public.automations for select to authenticated using (public.is_org_member(organization_id) and public.has_feature(organization_id,'automations'));
create policy automation_runs_select_member on public.automation_runs for select to authenticated using (public.is_org_member(organization_id) and public.has_feature(organization_id,'automations'));
-- Escrita é centralizada nas RPCs/trigger para validar JSON e preservar logs.

create or replace function public.save_automation(
  p_organization_id uuid,
  p_automation_id uuid,
  p_name text,
  p_trigger_event text,
  p_conditions jsonb,
  p_actions jsonb,
  p_active boolean
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_id uuid; v_action jsonb; v_type text; v_condition_key text;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin']) or not public.has_feature(p_organization_id,'automations') then raise exception 'forbidden'; end if;
  if char_length(trim(coalesce(p_name,'')))<2 then raise exception 'invalid name'; end if;
  if p_trigger_event not in('lead_created','quote_created','quote_link_enabled','quote_viewed','quote_response','appointment_created','appointment_status_changed') then raise exception 'invalid trigger'; end if;
  if jsonb_typeof(coalesce(p_conditions,'{}'::jsonb))<>'object' or jsonb_typeof(p_actions)<>'array' or jsonb_array_length(p_actions) not between 1 and 10 then raise exception 'invalid automation'; end if;
  for v_condition_key in select jsonb_object_keys(coalesce(p_conditions,'{}'::jsonb)) loop
    if v_condition_key not in('source','status','tag','min_value_cents') then raise exception 'unsupported condition'; end if;
  end loop;
  if p_conditions ? 'source' and (jsonb_typeof(p_conditions->'source')<>'string' or char_length(trim(p_conditions->>'source')) not between 1 and 80) then raise exception 'invalid source condition'; end if;
  if p_conditions ? 'status' and (jsonb_typeof(p_conditions->'status')<>'string' or char_length(trim(p_conditions->>'status')) not between 1 and 80) then raise exception 'invalid status condition'; end if;
  if p_conditions ? 'tag' and (jsonb_typeof(p_conditions->'tag')<>'string' or char_length(trim(p_conditions->>'tag')) not between 1 and 50) then raise exception 'invalid tag condition'; end if;
  if p_conditions ? 'min_value_cents' and (jsonb_typeof(p_conditions->'min_value_cents')<>'number' or (p_conditions->>'min_value_cents')::numeric < 0 or mod((p_conditions->>'min_value_cents')::numeric,1)<>0) then raise exception 'invalid minimum value condition'; end if;
  for v_action in select value from jsonb_array_elements(p_actions) loop
    v_type:=v_action->>'type';
    if v_type not in('create_task','add_tag','move_stage','notify_team') then raise exception 'unsupported action'; end if;
    if v_type='add_tag' and char_length(trim(coalesce(v_action->>'tag','')))<1 then raise exception 'invalid tag'; end if;
    if v_type='move_stage' and char_length(trim(coalesce(v_action->>'stage_key','')))<1 then raise exception 'invalid stage'; end if;
    if v_type='create_task' and char_length(trim(coalesce(v_action->>'title','')))<2 then raise exception 'invalid task'; end if;
    if v_type='notify_team' and char_length(trim(coalesce(v_action->>'title','')))<2 then raise exception 'invalid notification'; end if;
  end loop;
  if p_automation_id is null then
    insert into public.automations(organization_id,name,trigger_event,conditions,actions,active,created_by)
    values(p_organization_id,trim(p_name),p_trigger_event,coalesce(p_conditions,'{}'::jsonb),p_actions,p_active,auth.uid()) returning id into v_id;
  else
    update public.automations set name=trim(p_name),trigger_event=p_trigger_event,conditions=coalesce(p_conditions,'{}'::jsonb),actions=p_actions,active=p_active,updated_at=now()
    where id=p_automation_id and organization_id=p_organization_id returning id into v_id;
    if v_id is null then raise exception 'automation not found'; end if;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id)
  values(p_organization_id,auth.uid(),case when p_automation_id is null then 'automation.created' else 'automation.updated' end,'automation',v_id);
  return v_id;
end; $$;
revoke all on function public.save_automation(uuid,uuid,text,text,jsonb,jsonb,boolean) from public;
grant execute on function public.save_automation(uuid,uuid,text,text,jsonb,jsonb,boolean) to authenticated;

create or replace function public.set_automation_active(p_organization_id uuid,p_automation_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin']) or not public.has_feature(p_organization_id,'automations') then raise exception 'forbidden'; end if;
  update public.automations set active=p_active,updated_at=now() where id=p_automation_id and organization_id=p_organization_id;
  if not found then raise exception 'automation not found'; end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_organization_id,auth.uid(),'automation.active_changed','automation',p_automation_id,jsonb_build_object('active',p_active));
end; $$;
revoke all on function public.set_automation_active(uuid,uuid,boolean) from public;
grant execute on function public.set_automation_active(uuid,uuid,boolean) to authenticated;

create or replace function public.dry_run_automation(p_organization_id uuid,p_automation_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_auto public.automations%rowtype; v_run uuid;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin']) or not public.has_feature(p_organization_id,'automations') then raise exception 'forbidden'; end if;
  select * into v_auto from public.automations where id=p_automation_id and organization_id=p_organization_id;
  if v_auto.id is null then raise exception 'automation not found'; end if;
  insert into public.automation_runs(organization_id,automation_id,status,reason,actions_log)
  values(p_organization_id,v_auto.id,'dry_run','Configuração validada; nenhuma ação foi executada.',v_auto.actions) returning id into v_run;
  return jsonb_build_object('run_id',v_run,'trigger_event',v_auto.trigger_event,'conditions',v_auto.conditions,'actions',v_auto.actions,'executed',false);
end; $$;
revoke all on function public.dry_run_automation(uuid,uuid) from public;
grant execute on function public.dry_run_automation(uuid,uuid) to authenticated;

create or replace function public.process_automation_event()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_auto public.automations%rowtype; v_conditions jsonb; v_action jsonb; v_type text; v_match boolean; v_reason text;
  v_lead public.leads%rowtype; v_quote public.quotes%rowtype; v_appointment public.appointments%rowtype;
  v_lead_id uuid; v_customer_id uuid; v_log jsonb; v_status text; v_failed boolean; v_assigned uuid; v_stage uuid; v_priority text; v_due integer; v_min_value bigint;
begin
  if not public.organization_has_entitlement(new.organization_id,'automations') then return new; end if;
  for v_auto in select * from public.automations a where a.organization_id=new.organization_id and a.active=true and a.trigger_event=new.event_type order by a.created_at loop
    if exists(select 1 from public.automation_runs r where r.automation_id=v_auto.id and r.source_event_id=new.id) then continue; end if;
    v_conditions:=coalesce(v_auto.conditions,'{}'::jsonb); v_match:=true; v_reason:=null; v_lead_id:=null; v_customer_id:=null;
    if new.entity_type='lead' and new.entity_id is not null then select * into v_lead from public.leads where id=new.entity_id and organization_id=new.organization_id; v_lead_id:=v_lead.id; end if;
    if new.entity_type='quote' and new.entity_id is not null then select * into v_quote from public.quotes where id=new.entity_id and organization_id=new.organization_id; v_lead_id:=v_quote.lead_id; v_customer_id:=v_quote.customer_id; if v_lead_id is not null then select * into v_lead from public.leads where id=v_lead_id; end if; end if;
    if new.entity_type='appointment' and new.entity_id is not null then select * into v_appointment from public.appointments where id=new.entity_id and organization_id=new.organization_id; v_lead_id:=v_appointment.lead_id; v_customer_id:=v_appointment.customer_id; if v_lead_id is not null then select * into v_lead from public.leads where id=v_lead_id; end if; end if;

    if v_conditions ? 'source' then
      if new.entity_type='appointment' then v_match:=coalesce(new.metadata->>'source','')=v_conditions->>'source';
      elsif v_lead.id is not null then v_match:=coalesce(v_lead.source,'')=v_conditions->>'source'; else v_match:=false; end if;
      if not v_match then v_reason:='source condition not met'; end if;
    end if;
    if v_match and v_conditions ? 'status' then
      if new.entity_type='quote' then v_match:=coalesce(new.metadata->>'status',v_quote.status,'')=v_conditions->>'status';
      elsif new.entity_type='appointment' then v_match:=coalesce(new.metadata->>'status',v_appointment.status,'')=v_conditions->>'status';
      elsif v_lead.id is not null then v_match:=coalesce(v_lead.status,'')=v_conditions->>'status'; else v_match:=false; end if;
      if not v_match then v_reason:='status condition not met'; end if;
    end if;
    if v_match and v_conditions ? 'tag' then
      v_match:=v_lead.id is not null and (v_conditions->>'tag')=any(coalesce(v_lead.tags,'{}'::text[])); if not v_match then v_reason:='tag condition not met'; end if;
    end if;
    if v_match and v_conditions ? 'min_value_cents' then
      begin
        v_min_value:=greatest(0,(v_conditions->>'min_value_cents')::bigint);
        if new.entity_type='quote' then v_match:=coalesce(v_quote.total_cents,0)>=v_min_value;
        elsif v_lead.id is not null then v_match:=coalesce(v_lead.potential_value_cents,0)>=v_min_value; else v_match:=false; end if;
        if not v_match then v_reason:='minimum value condition not met'; end if;
      exception when others then
        v_match:=false; v_reason:='invalid minimum value condition';
      end;
    end if;

    if not v_match then
      insert into public.automation_runs(organization_id,automation_id,source_event_id,status,reason)
      values(new.organization_id,v_auto.id,new.id,'ignored',coalesce(v_reason,'conditions not met')) on conflict(automation_id,source_event_id) do nothing;
      continue;
    end if;

    v_log:='[]'::jsonb; v_failed:=false;
    for v_action in select value from jsonb_array_elements(v_auto.actions) loop
      v_type:=v_action->>'type';
      begin
        if v_type='create_task' then
          v_priority:=coalesce(nullif(v_action->>'priority',''),'medium'); if v_priority not in('low','medium','high','urgent') then v_priority:='medium'; end if;
          begin v_due:=greatest(0,least(coalesce((v_action->>'due_minutes')::integer,0),43200)); exception when others then v_due:=0; end;
          v_assigned:=null; if coalesce(v_action->>'assigned_to','')<>'' then begin v_assigned:=(v_action->>'assigned_to')::uuid; exception when others then v_assigned:=null; end; end if;
          if v_assigned is not null and not exists(select 1 from public.organization_members where organization_id=new.organization_id and user_id=v_assigned and status='active') then v_assigned:=null; end if;
          insert into public.tasks(organization_id,lead_id,customer_id,title,description,assigned_to,priority,due_at,status,created_by)
          values(new.organization_id,v_lead_id,v_customer_id,left(trim(v_action->>'title'),200),nullif(left(coalesce(v_action->>'description',''),2000),''),v_assigned,v_priority,case when v_due>0 then now()+make_interval(mins=>v_due) else null end,'open',v_auto.created_by);
        elsif v_type='add_tag' then
          if v_lead_id is null then raise exception 'lead unavailable'; end if;
          update public.leads set tags=array(select distinct x from unnest(tags||array[left(trim(v_action->>'tag'),50)]) x),updated_at=now() where id=v_lead_id and organization_id=new.organization_id;
        elsif v_type='move_stage' then
          if v_lead_id is null then raise exception 'lead unavailable'; end if;
          select ps.id into v_stage from public.pipeline_stages ps join public.leads l on l.pipeline_id=ps.pipeline_id where l.id=v_lead_id and l.organization_id=new.organization_id and ps.stage_key=v_action->>'stage_key' limit 1;
          if v_stage is null then raise exception 'stage unavailable'; end if;
          update public.leads set stage_id=v_stage,status=case when (v_action->>'stage_key')='won' then 'won' when (v_action->>'stage_key')='lost' then 'lost' else status end,updated_at=now() where id=v_lead_id;
        elsif v_type='notify_team' then
          insert into public.notifications(organization_id,user_id,kind,title,body,entity_type,entity_id)
          select new.organization_id,m.user_id,'info',left(trim(v_action->>'title'),160),nullif(left(coalesce(v_action->>'body',''),1000),''),new.entity_type,new.entity_id
          from public.organization_members m where m.organization_id=new.organization_id and m.status='active';
        else
          raise exception 'unsupported action';
        end if;
        v_log:=v_log||jsonb_build_array(jsonb_build_object('type',v_type,'status','executed'));
      exception when others then
        v_failed:=true; v_log:=v_log||jsonb_build_array(jsonb_build_object('type',coalesce(v_type,'unknown'),'status','failed','reason',left(sqlerrm,300)));
      end;
    end loop;
    v_status:=case when v_failed then 'failed' else 'executed' end;
    insert into public.automation_runs(organization_id,automation_id,source_event_id,status,reason,actions_log)
    values(new.organization_id,v_auto.id,new.id,v_status,case when v_failed then 'Uma ou mais ações falharam.' else null end,v_log)
    on conflict(automation_id,source_event_id) do nothing;
  end loop;
  return new;
end; $$;
revoke all on function public.process_automation_event() from public;
revoke all on function public.process_automation_event() from anon;
revoke all on function public.process_automation_event() from authenticated;

create trigger events_process_automations
after insert on public.events
for each row execute procedure public.process_automation_event();
