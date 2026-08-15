-- 2026-08-15 — Observabilidade segura da API pública e retry manual de Webhooks falhados.
-- Não armazena/exibe corpo, Authorization, IP, API key completa ou segredo de assinatura.

create or replace function public.list_api_request_logs(
  p_organization_id uuid,
  p_limit integer default 50
)
returns table(
  id bigint,
  key_prefix text,
  scope text,
  method text,
  route text,
  response_status integer,
  duration_ms integer,
  request_id text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path=public
as $$
  select
    l.id,
    coalesce(k.key_prefix,'revogada') as key_prefix,
    l.scope,
    l.method,
    l.route,
    l.response_status,
    l.duration_ms,
    l.request_id,
    l.created_at
  from public.api_request_logs l
  left join public.api_keys k on k.id=l.api_key_id
  where l.organization_id=p_organization_id
    and public.has_org_role(p_organization_id,array['owner','admin'])
    and public.has_feature(p_organization_id,'public_api')
  order by l.created_at desc
  limit least(greatest(coalesce(p_limit,50),1),200);
$$;
revoke all on function public.list_api_request_logs(uuid,integer) from public;
grant execute on function public.list_api_request_logs(uuid,integer) to authenticated;

create or replace function public.retry_webhook_delivery(
  p_organization_id uuid,
  p_delivery_id uuid
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_delivery public.webhook_deliveries%rowtype;
  v_endpoint public.webhook_endpoints%rowtype;
  v_job public.external_outbox%rowtype;
begin
  if auth.uid() is null
     or not public.has_org_role(p_organization_id,array['owner','admin'])
     or not public.has_feature(p_organization_id,'outbound_webhooks') then
    raise exception 'forbidden';
  end if;

  select * into v_delivery
  from public.webhook_deliveries
  where id=p_delivery_id and organization_id=p_organization_id
  for update;
  if v_delivery.id is null then raise exception 'delivery not found'; end if;
  if v_delivery.status<>'failed' then raise exception 'delivery is not failed'; end if;

  select * into v_endpoint
  from public.webhook_endpoints
  where id=v_delivery.endpoint_id and organization_id=p_organization_id
  for update;
  if v_endpoint.id is null or v_endpoint.status<>'active' then
    raise exception 'webhook endpoint is not active';
  end if;

  select * into v_job
  from public.external_outbox
  where organization_id=p_organization_id
    and provider='client_webhook'
    and entity_type='webhook_delivery'
    and entity_id=p_delivery_id
  order by created_at desc
  limit 1
  for update;
  if v_job.id is null then raise exception 'outbox job not found'; end if;
  if v_job.status<>'dead_letter' then raise exception 'outbox job is not dead letter'; end if;

  update public.external_outbox
  set status='pending',attempts=0,available_at=now(),locked_at=null,locked_by=null,
      provider_message_id=null,last_error=null,sent_at=null,updated_at=now()
  where id=v_job.id;

  update public.webhook_deliveries
  set status='queued',attempts=0,response_status=null,last_error=null,delivered_at=null,updated_at=now()
  where id=p_delivery_id;

  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(
    p_organization_id,auth.uid(),'webhook_delivery.manual_retry','webhook_delivery',p_delivery_id,
    jsonb_build_object('endpoint_id',v_delivery.endpoint_id,'event_type',v_delivery.event_type,'outbox_job_id',v_job.id)
  );
end;
$$;
revoke all on function public.retry_webhook_delivery(uuid,uuid) from public;
grant execute on function public.retry_webhook_delivery(uuid,uuid) to authenticated;
