-- 2026-08-15 — Webhooks do Resend: auditoria idempotente e atualização de entrega real.

create table public.provider_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('resend','whatsapp_cloud')),
  provider_event_id text not null,
  event_type text not null,
  provider_message_id text,
  occurred_at timestamptz,
  error_message text,
  created_at timestamptz not null default now(),
  unique(provider,provider_event_id)
);
create index provider_webhook_events_message_idx on public.provider_webhook_events(provider,provider_message_id,created_at desc);
alter table public.provider_webhook_events enable row level security;
-- Sem policies: eventos assinados são infraestrutura interna, não payload para o tenant.

create or replace function public.service_record_resend_event(
  p_provider_event_id text,
  p_event_type text,
  p_email_id text,
  p_occurred_at timestamptz,
  p_error_message text default null
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare v_event uuid;v_type text:=lower(trim(coalesce(p_event_type,'')));
begin
  if char_length(trim(coalesce(p_provider_event_id,'')))<3 then raise exception 'invalid event id'; end if;
  if char_length(trim(coalesce(p_email_id,'')))<3 then raise exception 'invalid email id'; end if;
  if v_type not in ('email.sent','email.delivered','email.bounced','email.failed','email.suppressed','email.delivery_delayed','email.opened','email.clicked','email.complained') then
    raise exception 'unsupported resend event';
  end if;

  insert into public.provider_webhook_events(provider,provider_event_id,event_type,provider_message_id,occurred_at,error_message)
  values('resend',trim(p_provider_event_id),v_type,trim(p_email_id),coalesce(p_occurred_at,now()),nullif(left(coalesce(p_error_message,''),1000),''))
  on conflict(provider,provider_event_id) do nothing returning id into v_event;
  if v_event is null then return false; end if;

  if v_type='email.sent' then
    update public.communication_messages set
      status=case when status='queued' then 'sent' else status end,
      sent_at=case when status='queued' then coalesce(p_occurred_at,now()) else sent_at end
    where provider='resend' and provider_message_id=trim(p_email_id);
  elsif v_type='email.delivered' then
    update public.communication_messages set
      status='delivered',
      sent_at=coalesce(sent_at,coalesce(p_occurred_at,now())),
      delivered_at=coalesce(delivered_at,coalesce(p_occurred_at,now())),
      error_code=null,error_message=null
    where provider='resend' and provider_message_id=trim(p_email_id) and status<>'failed';
  elsif v_type in ('email.bounced','email.failed','email.suppressed') then
    update public.communication_messages set
      status='failed',error_code=left(v_type,100),
      error_message=coalesce(nullif(left(coalesce(p_error_message,''),1000),''),v_type)
    where provider='resend' and provider_message_id=trim(p_email_id) and status<>'delivered';
  end if;

  return true;
end;
$$;
revoke all on function public.service_record_resend_event(text,text,text,timestamptz,text) from public, anon, authenticated;
grant execute on function public.service_record_resend_event(text,text,text,timestamptz,text) to service_role;
