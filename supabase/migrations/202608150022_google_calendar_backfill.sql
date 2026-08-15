-- 2026-08-15 — Backfill seguro do Google Calendar após OAuth.
-- O callback server-side chama esta RPC com a chave única do fluxo OAuth.
create or replace function public.service_enqueue_google_calendar_backfill(
  p_organization_id uuid,
  p_sync_key text
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_count integer:=0;
begin
  if auth.role()<>'service_role' then raise exception 'forbidden'; end if;
  if p_sync_key is null or char_length(p_sync_key)<8 or char_length(p_sync_key)>120 then
    raise exception 'invalid sync key';
  end if;
  if not public.organization_has_entitlement(p_organization_id,'google_calendar') then return 0; end if;
  if not exists(
    select 1 from public.integration_connections c
    where c.organization_id=p_organization_id
      and c.provider='google_calendar'
      and c.status='active'
  ) then return 0; end if;

  insert into public.external_outbox(
    organization_id,provider,kind,entity_type,entity_id,payload,dedupe_key
  )
  select
    a.organization_id,
    'google_calendar',
    'calendar_upsert_appointment',
    'appointment',
    a.id,
    jsonb_build_object('source','google_calendar_connection','sync_key',p_sync_key),
    'google_calendar:backfill:'||p_sync_key||':appointment:'||a.id::text
  from public.appointments a
  where a.organization_id=p_organization_id
    and a.status in ('scheduled','confirmed')
    and a.ends_at>now()
  on conflict(dedupe_key) do nothing;

  get diagnostics v_count=row_count;
  return v_count;
end;
$$;
revoke all on function public.service_enqueue_google_calendar_backfill(uuid,text) from public,anon,authenticated;
grant execute on function public.service_enqueue_google_calendar_backfill(uuid,text) to service_role;
