-- Visão agregada de consumo de IA para administradores da plataforma.
-- Não expõe prompts, respostas ou dados de leads; apenas métricas operacionais.
create or replace function public.admin_ai_usage_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_month_start timestamptz := date_trunc('month', now());
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception 'forbidden';
  end if;

  return jsonb_build_object(
    'period_start', v_month_start,
    'requests', (select count(*) from public.ai_usage where created_at >= v_month_start),
    'successful_requests', (select count(*) from public.ai_usage where created_at >= v_month_start and status = 'succeeded'),
    'failed_requests', (select count(*) from public.ai_usage where created_at >= v_month_start and status = 'failed'),
    'tokens', coalesce((select sum(total_tokens) from public.ai_usage where created_at >= v_month_start), 0),
    'estimated_cost_usd_micros', coalesce((select sum(estimated_cost_usd_micros) from public.ai_usage where created_at >= v_month_start), 0),
    'organizations_using_ai', (select count(distinct organization_id) from public.ai_usage where created_at >= v_month_start),
    'resources', coalesce((
      select jsonb_agg(jsonb_build_object(
        'resource', resource,
        'requests', requests,
        'tokens', tokens,
        'estimated_cost_usd_micros', estimated_cost_usd_micros
      ) order by requests desc, resource)
      from (
        select
          resource,
          count(*)::bigint as requests,
          coalesce(sum(total_tokens), 0)::bigint as tokens,
          coalesce(sum(estimated_cost_usd_micros), 0)::bigint as estimated_cost_usd_micros
        from public.ai_usage
        where created_at >= v_month_start
        group by resource
      ) r
    ), '[]'::jsonb),
    'organizations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'organization_id', organization_id,
        'organization_name', organization_name,
        'requests', requests,
        'successful_requests', successful_requests,
        'failed_requests', failed_requests,
        'tokens', tokens,
        'estimated_cost_usd_micros', estimated_cost_usd_micros
      ) order by requests desc, organization_name)
      from (
        select
          u.organization_id,
          o.name as organization_name,
          count(*)::bigint as requests,
          count(*) filter (where u.status = 'succeeded')::bigint as successful_requests,
          count(*) filter (where u.status = 'failed')::bigint as failed_requests,
          coalesce(sum(u.total_tokens), 0)::bigint as tokens,
          coalesce(sum(u.estimated_cost_usd_micros), 0)::bigint as estimated_cost_usd_micros
        from public.ai_usage u
        join public.organizations o on o.id = u.organization_id
        where u.created_at >= v_month_start
        group by u.organization_id, o.name
        order by count(*) desc, o.name
        limit 50
      ) org_usage
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.admin_ai_usage_summary() from public;
grant execute on function public.admin_ai_usage_summary() to authenticated;
