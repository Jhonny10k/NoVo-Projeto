-- 2026-08-15 — Defesa em profundidade para comunicações/notificações em organizações multiunidade.
-- Garante que destinatários internos não recebam conteúdo de uma filial à qual não possuem acesso.

create or replace function public.guard_notification_unit_scope()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_unit uuid;
begin
  if new.user_id is null or not public.organization_has_entitlement(new.organization_id,'multi_unit') or new.entity_id is null then
    return new;
  end if;

  case new.entity_type
    when 'lead' then select unit_id into v_unit from public.leads where organization_id=new.organization_id and id=new.entity_id;
    when 'customer' then select unit_id into v_unit from public.customers where organization_id=new.organization_id and id=new.entity_id;
    when 'quote' then select unit_id into v_unit from public.quotes where organization_id=new.organization_id and id=new.entity_id;
    when 'task' then select unit_id into v_unit from public.tasks where organization_id=new.organization_id and id=new.entity_id;
    when 'appointment' then select unit_id into v_unit from public.appointments where organization_id=new.organization_id and id=new.entity_id;
    else v_unit:=null;
  end case;

  if v_unit is not null and not public.user_can_access_unit(new.organization_id,new.user_id,v_unit) then
    return null;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_notification_unit_scope() from public,anon,authenticated;

drop trigger if exists notifications_guard_unit_scope on public.notifications;
create trigger notifications_guard_unit_scope
before insert on public.notifications
for each row execute procedure public.guard_notification_unit_scope();

create or replace function public.guard_external_outbox_unit_recipient()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_unit uuid;
begin
  if new.recipient_user_id is null or new.source_event_id is null or not public.organization_has_entitlement(new.organization_id,'multi_unit') then
    return new;
  end if;
  select unit_id into v_unit from public.events where id=new.source_event_id and organization_id=new.organization_id;
  if v_unit is not null and not public.user_can_access_unit(new.organization_id,new.recipient_user_id,v_unit) then
    return null;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_external_outbox_unit_recipient() from public,anon,authenticated;

drop trigger if exists external_outbox_guard_unit_recipient on public.external_outbox;
create trigger external_outbox_guard_unit_recipient
before insert on public.external_outbox
for each row execute procedure public.guard_external_outbox_unit_recipient();
