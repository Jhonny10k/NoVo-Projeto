-- 2026-08-15 — Hardening final após Supabase Security Advisor.
-- Revoga EXECUTE anônimo de SECURITY DEFINER por padrão e reabre somente RPCs públicas deliberadas.

alter function public.set_updated_at() set search_path = public;
alter function public.safe_slug(text) set search_path = public;

-- btree_gist foi instalada para Agenda, mas não há índice/exclusion constraint GiST dependente dela.
-- Os operadores tstzrange usados pela aplicação são nativos do PostgreSQL.
drop extension if exists btree_gist;

-- Supabase/Postgres pode conceder EXECUTE a PUBLIC por padrão em funções novas.
-- Fechamos todas as SECURITY DEFINER e depois reabrimos apenas a allowlist pública.
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
  loop
    execute format('revoke execute on function %s from public, anon', r.signature);
  end loop;
end
$$;

-- RPCs públicas deliberadas. Elas retornam apenas projeções públicas e/ou validam inputs internamente.
grant execute on function public.get_public_site(text) to anon, authenticated;
grant execute on function public.get_public_quote(text) to anon, authenticated;
grant execute on function public.respond_public_quote(text,text) to anon, authenticated;
grant execute on function public.public_create_quote_request(text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.public_create_quote_request(text,text,text,text,text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.get_public_booking(text) to anon, authenticated;
grant execute on function public.public_create_appointment(text,uuid,text,text,text) to anon, authenticated;
grant execute on function public.resolve_public_custom_domain(text) to anon, authenticated;
grant execute on function public.get_public_branding(text) to anon, authenticated;
grant execute on function public.list_public_sites() to anon, authenticated;

-- Funções service_* são exclusivamente backend/service role.
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and p.proname like 'service\_%' escape '\\'
  loop
    execute format('revoke execute on function %s from authenticated', r.signature);
    execute format('grant execute on function %s to service_role', r.signature);
  end loop;
end
$$;

-- Helpers/Workers internos que não são endpoints RPC de usuário.
revoke execute on function public.apply_coupon_redemption(uuid) from authenticated;
revoke execute on function public.record_site_visit(text,text,text,text,text,text,text,text,text) from authenticated;
revoke execute on function public.run_temporal_automations(timestamptz,integer) from authenticated;
revoke execute on function public.execute_temporal_automation_actions(uuid,uuid,uuid,text,uuid,text) from authenticated;
revoke execute on function public.organization_analytics_summary_orgwide(uuid,integer) from authenticated;
revoke execute on function public.organization_has_entitlement(uuid,text) from authenticated;
revoke execute on function public.user_can_access_unit(uuid,uuid,uuid) from authenticated;

grant execute on function public.apply_coupon_redemption(uuid) to service_role;
grant execute on function public.record_site_visit(text,text,text,text,text,text,text,text,text) to service_role;
grant execute on function public.run_temporal_automations(timestamptz,integer) to service_role;
grant execute on function public.execute_temporal_automation_actions(uuid,uuid,uuid,text,uuid,text) to service_role;

-- Tabelas internas são acessadas somente via RPC/backend. RLS já é deny-by-default;
-- removemos também privilégios diretos da role authenticated por least privilege.
revoke all privileges on table public.api_keys from authenticated;
revoke all privileges on table public.api_request_logs from authenticated;
revoke all privileges on table public.api_usage_windows from authenticated;
revoke all privileges on table public.billing_webhook_events from authenticated;
revoke all privileges on table public.coupon_redemptions from authenticated;
revoke all privileges on table public.coupons from authenticated;
revoke all privileges on table public.custom_domains from authenticated;
revoke all privileges on table public.external_outbox from authenticated;
revoke all privileges on table public.integration_secrets from authenticated;
revoke all privileges on table public.oauth_states from authenticated;
revoke all privileges on table public.provider_webhook_events from authenticated;
revoke all privileges on table public.rate_limit_windows from authenticated;
revoke all privileges on table public.webhook_deliveries from authenticated;
revoke all privileges on table public.webhook_endpoint_secrets from authenticated;
revoke all privileges on table public.webhook_endpoints from authenticated;
