-- 2026-08-15 — Hardening de ACL para funções SECURITY DEFINER internas.
-- Funções de trigger não precisam ser executáveis por clientes REST/Auth.
-- O trigger continua podendo invocá-las normalmente após o REVOKE.

revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.activate_invited_memberships() from public, anon, authenticated;
revoke all on function public.initialize_organization_trial() from public, anon, authenticated;
revoke all on function public.initialize_site_sections() from public, anon, authenticated;
revoke all on function public.enforce_quote_request_entitlement() from public, anon, authenticated;

-- Garantias adicionais para helpers internos que só são consumidos por outras funções/triggers.
revoke all on function public.organization_has_entitlement(uuid,text) from public, anon, authenticated;
revoke all on function public.user_can_access_unit(uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function public.sync_commercial_unit() from public, anon, authenticated;
revoke all on function public.sync_event_unit() from public, anon, authenticated;
