-- 2026-08-15 — Automações temporais: lead sem contato, cliente inativo e data específica.
-- O scheduler é executado por Supabase Cron/pg_cron chamando run_temporal_automations.

alter table public.automations drop constraint if exists automations_trigger_event_check;
alter table public.automations add constraint automations_trigger_event_check check (
  trigger_event in (
    'lead_created','quote_created','quote_link_enabled','quote_viewed','quote_response',
    'appointment_created','appointment_status_changed',
    'lead_no_response','customer_inactive','date_specific'
  )
);

alter table public.automation_runs add column if not exists dedupe_key text;
create unique index if not exists automation_runs_automation_dedupe_uidx
  on public.automation_runs(automation_id,dedupe_key)
  where dedupe_key is not null;

-- Mantém a mesma assinatura usada pelo aplicativo, ampliando a validação para gatilhos temporais.
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
declare
  v_id uuid; v_action jsonb; v_type text; v_condition_key text;
  v_after integer; v_days integer; v_run_local timestamp; v_timezone text;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin']) or not public.has_feature(p_organization_id,'automations') then raise exception 'forbidden'; end if;
  if char_length(trim(coalesce(p_name,'')))<2 then raise exception 'invalid name'; end if;
  if p_trigger_event not in(
    'lead_created','quote_created','quote_link_enabled','quote_viewed','quote_response',
    'appointment_created','appointment_status_changed','lead_no_response','customer_inactive','date_specific'
  ) then raise exception 'invalid trigger'; end if;
  if jsonb_typeof(coalesce(p_conditions,'{}'::jsonb))<>'object' or jsonb_typeof(p_actions)<>'array' or jsonb_array_length(p_actions) not between 1 and 10 then raise exception 'invalid automation'; end if;

  for v_condition_key in select jsonb_object_keys(coalesce(p_conditions,'{}'::jsonb)) loop
    if v_condition_key not in('source','status','tag','min_value_cents','after_minutes','inactive_days','run_at_local') then raise exception 'unsupported condition'; end if;
  end loop;
  if p_conditions ? 'source' and (jsonb_typeof(p_conditions->'source')<>'string' or char_length(trim(p_conditions->>'source')) not between 1 and 80) then raise exception 'invalid source condition'; end if;
  if p_conditions ? 'status' and (jsonb_typeof(p_conditions->'status')<>'string' or char_length(trim(p_conditions->>'status')) not between 1 and 80) then raise exception 'invalid status condition'; end if;
  if p_conditions ? 'tag' and (jsonb_typeof(p_conditions->'tag')<>'string' or char_length(trim(p_conditions->>'tag')) not between 1 and 50) then raise exception 'invalid tag condition'; end if;
  if p_conditions ? 'min_value_cents' and (jsonb_typeof(p_conditions->'min_value_cents')<>'number' or (p_conditions->>'min_value_cents')::numeric < 0 or mod((p_conditions->>'min_value_cents')::numeric,1)<>0) then raise exception 'invalid minimum value condition'; end if;

  if p_trigger_event='lead_no_response' then
    begin v_after:=(p_conditions->>'after_minutes')::integer; exception when others then v_after:=null; end;
    if v_after is null or v_after not between 15 and 525600 then raise exception 'invalid response interval'; end if;
    if p_conditions ? 'inactive_days' or p_conditions ? 'run_at_local' then raise exception 'invalid temporal condition'; end if;
  elsif p_trigger_event='customer_inactive' then
    begin v_days:=(p_conditions->>'inactive_days')::integer; exception when others then v_days:=null; end;
    if v_days is null or v_days not between 1 and 3650 then raise exception 'invalid inactivity interval'; end if;
    if p_conditions ? 'source' or p_conditions ? 'status' or p_conditions ? 'tag' or p_conditions ? 'min_value_cents' or p_conditions ? 'after_minutes' or p_conditions ? 'run_at_local' then raise exception 'invalid customer inactivity condition'; end if;
  elsif p_trigger_event='date_specific' then
    if jsonb_typeof(p_conditions->'run_at_local')<>'string' then raise exception 'invalid scheduled date'; end if;
    begin v_run_local:=(p_conditions->>'run_at_local')::timestamp; exception when others then v_run_local:=null; end;
    select timezone into v_timezone from public.organizations where id=p_organization_id;
    if v_run_local is null or (v_run_local at time zone coalesce(v_timezone,'America/Sao_Paulo')) <= now() then raise exception 'scheduled date must be in the future'; end if;
    if p_conditions ? 'source' or p_conditions ? 'status' or p_conditions ? 'tag' or p_conditions ? 'min_value_cents' or p_conditions ? 'after_minutes' or p_conditions ? 'inactive_days' then raise exception 'invalid scheduled condition'; end if;
  elsif p_conditions ? 'after_minutes' or p_conditions ? 'inactive_days' or p_conditions ? 'run_at_local' then
    raise exception 'temporal condition requires temporal trigger';
  end if;

  for v_action in select value from jsonb_array_elements(p_actions) loop
    v_type:=v_action->>'type';
    if v_type not in('create_task','add_tag','move_stage','notify_team') then raise exception 'unsupported action'; end if;
    if v_type='add_tag' and char_length(trim(coalesce(v_action->>'tag','')))<1 then raise exception 'invalid tag'; end if;
    if v_type='move_stage' and char_length(trim(coalesce(v_action->>'stage_key','')))<1 then raise exception 'invalid stage'; end if;
    if v_type='create_task' and char_length(trim(coalesce(v_action->>'title','')))<2 then raise exception 'invalid task'; end if;
    if v_type='notify_team' and char_length(trim(coalesce(v_action->>'title','')))<2 then raise exception 'invalid notification'; end if;
    if p_trigger_event in('customer_inactive','date_specific') and v_type in('add_tag','move_stage') then raise exception 'action requires lead context'; end if;
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

-- Executa somente ações internas já suportadas pelo motor V1. Função privada ao banco.
create or replace function public.execute_temporal_automation_actions(
  p_automation_id uuid,
  p_lead_id uuid,
  p_customer_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_dedupe_key text
)
returns text
language plpgsql
security definer
set search_path=public
as $$
declare
  v_auto public.automations%rowtype; v_action jsonb; v_type text; v_log jsonb:='[]'::jsonb;
  v_failed boolean:=false; v_assigned uuid; v_stage uuid; v_priority text; v_due integer; v_status text;
begin
  select * into v_auto from public.automations where id=p_automation_id and active=true;
  if v_auto.id is null or not public.organization_has_entitlement(v_auto.organization_id,'automations') then return 'ignored'; end if;
  if p_dedupe_key is null or exists(select 1 from public.automation_runs where automation_id=v_auto.id and dedupe_key=p_dedupe_key) then return 'ignored'; end if;

  for v_action in select value from jsonb_array_elements(v_auto.actions) loop
    v_type:=v_action->>'type';
    begin
      if v_type='create_task' then
        v_priority:=coalesce(nullif(v_action->>'priority',''),'medium'); if v_priority not in('low','medium','high','urgent') then v_priority:='medium'; end if;
        begin v_due:=greatest(0,least(coalesce((v_action->>'due_minutes')::integer,0),43200)); exception when others then v_due:=0; end;
        v_assigned:=null;
        if coalesce(v_action->>'assigned_to','')<>'' then begin v_assigned:=(v_action->>'assigned_to')::uuid; exception when others then v_assigned:=null; end; end if;
        if v_assigned is not null and not exists(select 1 from public.organization_members where organization_id=v_auto.organization_id and user_id=v_assigned and status='active') then v_assigned:=null; end if;
        insert into public.tasks(organization_id,lead_id,customer_id,title,description,assigned_to,priority,due_at,status,created_by)
        values(v_auto.organization_id,p_lead_id,p_customer_id,left(trim(v_action->>'title'),200),nullif(left(coalesce(v_action->>'description',''),2000),''),v_assigned,v_priority,case when v_due>0 then now()+make_interval(mins=>v_due) else null end,'open',v_auto.created_by);
      elsif v_type='add_tag' then
        if p_lead_id is null then raise exception 'lead unavailable'; end if;
        update public.leads set tags=array(select distinct x from unnest(tags||array[left(trim(v_action->>'tag'),50)]) x),updated_at=now()
        where id=p_lead_id and organization_id=v_auto.organization_id;
      elsif v_type='move_stage' then
        if p_lead_id is null then raise exception 'lead unavailable'; end if;
        select ps.id into v_stage from public.pipeline_stages ps join public.leads l on l.pipeline_id=ps.pipeline_id
        where l.id=p_lead_id and l.organization_id=v_auto.organization_id and ps.stage_key=v_action->>'stage_key' limit 1;
        if v_stage is null then raise exception 'stage unavailable'; end if;
        update public.leads set stage_id=v_stage,status=case when (v_action->>'stage_key')='won' then 'won' when (v_action->>'stage_key')='lost' then 'lost' else status end,updated_at=now() where id=p_lead_id;
      elsif v_type='notify_team' then
        insert into public.notifications(organization_id,user_id,kind,title,body,entity_type,entity_id)
        select v_auto.organization_id,m.user_id,'info',left(trim(v_action->>'title'),160),nullif(left(coalesce(v_action->>'body',''),1000),''),p_entity_type,p_entity_id
        from public.organization_members m where m.organization_id=v_auto.organization_id and m.status='active';
      else
        raise exception 'unsupported action';
      end if;
      v_log:=v_log||jsonb_build_array(jsonb_build_object('type',v_type,'status','executed'));
    exception when others then
      v_failed:=true;
      v_log:=v_log||jsonb_build_array(jsonb_build_object('type',coalesce(v_type,'unknown'),'status','failed','reason',left(sqlerrm,300)));
    end;
  end loop;

  v_status:=case when v_failed then 'failed' else 'executed' end;
  insert into public.automation_runs(organization_id,automation_id,status,reason,actions_log,dedupe_key)
  values(v_auto.organization_id,v_auto.id,v_status,case when v_failed then 'Uma ou mais ações falharam.' else null end,v_log,p_dedupe_key)
  on conflict (automation_id,dedupe_key) where dedupe_key is not null do nothing;
  return v_status;
end; $$;
revoke all on function public.execute_temporal_automation_actions(uuid,uuid,uuid,text,uuid,text) from public, anon, authenticated;

-- Chamado pelo Supabase Cron. O lock evita dois schedulers executando o mesmo lote em paralelo.
create or replace function public.run_temporal_automations(p_now timestamptz default now(), p_limit integer default 500)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_auto public.automations%rowtype; v_lead public.leads%rowtype; v_customer public.customers%rowtype;
  v_after integer; v_days integer; v_count integer:=0; v_run_at timestamptz; v_timezone text; v_last_activity timestamptz;
  v_key text; v_status text;
begin
  p_limit:=greatest(1,least(coalesce(p_limit,500),2000));
  if not pg_try_advisory_xact_lock(hashtextextended('platform_temporal_automations',0)) then
    return jsonb_build_object('processed',0,'busy',true);
  end if;

  for v_auto in
    select a.* from public.automations a
    where a.active=true and a.trigger_event in('lead_no_response','customer_inactive','date_specific')
      and public.organization_has_entitlement(a.organization_id,'automations')
    order by a.created_at
  loop
    exit when v_count>=p_limit;

    if v_auto.trigger_event='lead_no_response' then
      begin v_after:=(v_auto.conditions->>'after_minutes')::integer; exception when others then continue; end;
      if v_after not between 15 and 525600 then continue; end if;
      for v_lead in
        select l.* from public.leads l
        where l.organization_id=v_auto.organization_id
          and l.status not in('won','lost')
          and greatest(coalesce(l.last_contact_at,l.created_at),l.updated_at) <= p_now-make_interval(mins=>v_after)
          and (not(v_auto.conditions?'source') or l.source=v_auto.conditions->>'source')
          and (not(v_auto.conditions?'status') or l.status=v_auto.conditions->>'status')
          and (not(v_auto.conditions?'tag') or (v_auto.conditions->>'tag')=any(coalesce(l.tags,'{}'::text[])))
          and (not(v_auto.conditions?'min_value_cents') or coalesce(l.potential_value_cents,0)>=(v_auto.conditions->>'min_value_cents')::bigint)
        order by greatest(coalesce(l.last_contact_at,l.created_at),l.updated_at)
        limit greatest(1,p_limit-v_count)
      loop
        v_last_activity:=greatest(coalesce(v_lead.last_contact_at,v_lead.created_at),v_lead.updated_at);
        v_key:='lead_no_response:'||v_lead.id::text||':'||floor(extract(epoch from v_last_activity))::bigint::text;
        v_status:=public.execute_temporal_automation_actions(v_auto.id,v_lead.id,null,'lead',v_lead.id,v_key);
        if v_status<>'ignored' then v_count:=v_count+1; end if;
        exit when v_count>=p_limit;
      end loop;

    elsif v_auto.trigger_event='customer_inactive' then
      begin v_days:=(v_auto.conditions->>'inactive_days')::integer; exception when others then continue; end;
      if v_days not between 1 and 3650 then continue; end if;
      for v_customer in
        select c.* from public.customers c
        where c.organization_id=v_auto.organization_id
          and greatest(
            c.updated_at,
            coalesce((select max(q.updated_at) from public.quotes q where q.organization_id=c.organization_id and q.customer_id=c.id),c.updated_at),
            coalesce((select max(a.updated_at) from public.appointments a where a.organization_id=c.organization_id and a.customer_id=c.id),c.updated_at),
            coalesce((select max(t.updated_at) from public.tasks t where t.organization_id=c.organization_id and t.customer_id=c.id),c.updated_at)
          ) <= p_now-make_interval(days=>v_days)
        order by c.updated_at
        limit greatest(1,p_limit-v_count)
      loop
        select greatest(
          v_customer.updated_at,
          coalesce((select max(q.updated_at) from public.quotes q where q.organization_id=v_customer.organization_id and q.customer_id=v_customer.id),v_customer.updated_at),
          coalesce((select max(a.updated_at) from public.appointments a where a.organization_id=v_customer.organization_id and a.customer_id=v_customer.id),v_customer.updated_at),
          coalesce((select max(t.updated_at) from public.tasks t where t.organization_id=v_customer.organization_id and t.customer_id=v_customer.id),v_customer.updated_at)
        ) into v_last_activity;
        v_key:='customer_inactive:'||v_customer.id::text||':'||floor(extract(epoch from v_last_activity))::bigint::text;
        v_status:=public.execute_temporal_automation_actions(v_auto.id,null,v_customer.id,'customer',v_customer.id,v_key);
        if v_status<>'ignored' then v_count:=v_count+1; end if;
        exit when v_count>=p_limit;
      end loop;

    elsif v_auto.trigger_event='date_specific' then
      select timezone into v_timezone from public.organizations where id=v_auto.organization_id;
      begin v_run_at:=(v_auto.conditions->>'run_at_local')::timestamp at time zone coalesce(v_timezone,'America/Sao_Paulo'); exception when others then continue; end;
      if v_run_at<=p_now then
        v_key:='date_specific:'||v_auto.id::text||':'||floor(extract(epoch from v_run_at))::bigint::text;
        v_status:=public.execute_temporal_automation_actions(v_auto.id,null,null,'automation',v_auto.id,v_key);
        if v_status<>'ignored' then
          v_count:=v_count+1;
          update public.automations set active=false,updated_at=now() where id=v_auto.id;
        end if;
      end if;
    end if;
  end loop;

  return jsonb_build_object('processed',v_count,'busy',false,'ran_at',p_now);
end; $$;
revoke all on function public.run_temporal_automations(timestamptz,integer) from public, anon, authenticated;
grant execute on function public.run_temporal_automations(timestamptz,integer) to service_role;

comment on function public.run_temporal_automations(timestamptz,integer) is
'Executa gatilhos temporais. Em Supabase hospedado, agendar via Supabase Cron/pg_cron; não expor a usuários da aplicação.';
