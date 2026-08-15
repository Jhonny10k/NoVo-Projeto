-- 2026-08-15 — Observabilidade agregada de API/Webhooks/outbox para o admin master.
-- Somente metadados operacionais: nenhum payload, Authorization, IP, segredo, URL sensível ou corpo de resposta.

create or replace function public.admin_developer_observability(p_hours integer default 24)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_since timestamptz;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception 'forbidden';
  end if;

  p_hours := least(greatest(coalesce(p_hours,24),1),720);
  v_since := now() - make_interval(hours => p_hours);

  select jsonb_build_object(
    'hours', p_hours,
    'generated_at', now(),
    'api', jsonb_build_object(
      'requests', (select count(*) from public.api_request_logs l where l.created_at >= v_since),
      'errors', (select count(*) from public.api_request_logs l where l.created_at >= v_since and l.response_status >= 400),
      'organizations', (select count(distinct l.organization_id) from public.api_request_logs l where l.created_at >= v_since),
      'active_keys', (select count(*) from public.api_keys k where k.status='active' and (k.expires_at is null or k.expires_at>now())),
      'top_routes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'method',r.method,'route',r.route,'requests',r.requests,'errors',r.errors
        ) order by r.requests desc,r.route)
        from (
          select l.method,l.route,count(*)::bigint requests,
                 count(*) filter(where l.response_status>=400)::bigint errors
          from public.api_request_logs l
          where l.created_at>=v_since
          group by l.method,l.route
          order by count(*) desc,l.route
          limit 10
        ) r
      ),'[]'::jsonb),
      'top_organizations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'organization_id',r.organization_id,'organization_name',r.organization_name,
          'requests',r.requests,'errors',r.errors
        ) order by r.requests desc,r.organization_name)
        from (
          select o.id organization_id,o.name organization_name,count(*)::bigint requests,
                 count(*) filter(where l.response_status>=400)::bigint errors
          from public.api_request_logs l
          join public.organizations o on o.id=l.organization_id
          where l.created_at>=v_since
          group by o.id,o.name
          order by count(*) desc,o.name
          limit 10
        ) r
      ),'[]'::jsonb)
    ),
    'webhooks', jsonb_build_object(
      'deliveries', (select count(*) from public.webhook_deliveries d where d.created_at>=v_since),
      'delivered', (select count(*) from public.webhook_deliveries d where d.created_at>=v_since and d.status='delivered'),
      'failed', (select count(*) from public.webhook_deliveries d where d.created_at>=v_since and d.status='failed'),
      'active_endpoints', (select count(*) from public.webhook_endpoints e where e.status='active'),
      'dead_letters', (select count(*) from public.external_outbox o where o.provider='client_webhook' and o.status='dead_letter'),
      'top_organizations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'organization_id',r.organization_id,'organization_name',r.organization_name,
          'deliveries',r.deliveries,'delivered',r.delivered,'failed',r.failed
        ) order by r.deliveries desc,r.organization_name)
        from (
          select o.id organization_id,o.name organization_name,count(*)::bigint deliveries,
                 count(*) filter(where d.status='delivered')::bigint delivered,
                 count(*) filter(where d.status='failed')::bigint failed
          from public.webhook_deliveries d
          join public.organizations o on o.id=d.organization_id
          where d.created_at>=v_since
          group by o.id,o.name
          order by count(*) desc,o.name
          limit 10
        ) r
      ),'[]'::jsonb)
    ),
    'outbox', jsonb_build_object(
      'pending', (select count(*) from public.external_outbox o where o.status='pending'),
      'retry', (select count(*) from public.external_outbox o where o.status='retry'),
      'processing', (select count(*) from public.external_outbox o where o.status='processing'),
      'dead_letter', (select count(*) from public.external_outbox o where o.status='dead_letter'),
      'sent_window', (select count(*) from public.external_outbox o where o.status='sent' and o.sent_at>=v_since),
      'providers', coalesce((
        select jsonb_agg(jsonb_build_object(
          'provider',r.provider,'pending',r.pending,'retry',r.retry,
          'processing',r.processing,'dead_letter',r.dead_letter,'sent_window',r.sent_window
        ) order by r.provider)
        from (
          select o.provider,
                 count(*) filter(where o.status='pending')::bigint pending,
                 count(*) filter(where o.status='retry')::bigint retry,
                 count(*) filter(where o.status='processing')::bigint processing,
                 count(*) filter(where o.status='dead_letter')::bigint dead_letter,
                 count(*) filter(where o.status='sent' and o.sent_at>=v_since)::bigint sent_window
          from public.external_outbox o
          group by o.provider
        ) r
      ),'[]'::jsonb)
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.admin_developer_observability(integer) from public;
grant execute on function public.admin_developer_observability(integer) to authenticated;
