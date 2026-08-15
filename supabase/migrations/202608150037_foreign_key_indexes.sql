-- Migration 0037: add covering indexes for foreign keys reported by Supabase Performance Advisor.
-- These indexes improve FK checks, joins, deletes/updates on referenced rows and common lookups.
-- Composite unit-scoped FKs use one composite index, which also covers the organization_id prefix.

create index if not exists api_keys_created_by_idx on public.api_keys(created_by);
create index if not exists api_keys_revoked_by_idx on public.api_keys(revoked_by);
create index if not exists appointments_created_by_idx on public.appointments(created_by);
create index if not exists audit_logs_actor_user_idx on public.audit_logs(actor_user_id);
create index if not exists automations_created_by_idx on public.automations(created_by);
create index if not exists billing_checkout_created_by_idx on public.billing_checkout_sessions(created_by);
create index if not exists categories_created_by_idx on public.categories(created_by);
create index if not exists communication_messages_created_by_idx on public.communication_messages(created_by);
create index if not exists coupons_created_by_idx on public.coupons(created_by);
create index if not exists coupons_plan_idx on public.coupons(plan_id);
create index if not exists custom_domains_created_by_idx on public.custom_domains(created_by);
create index if not exists customers_created_by_idx on public.customers(created_by);
create index if not exists events_actor_user_idx on public.events(actor_user_id);
create index if not exists external_outbox_recipient_user_idx on public.external_outbox(recipient_user_id);
create index if not exists integration_connections_created_by_idx on public.integration_connections(created_by);
create index if not exists leads_created_by_idx on public.leads(created_by);
create index if not exists organization_branding_updated_by_idx on public.organization_branding(updated_by);
create index if not exists organization_member_units_created_by_idx on public.organization_member_units(created_by);
create index if not exists organization_units_created_by_idx on public.organization_units(created_by);
create index if not exists organizations_created_by_idx on public.organizations(created_by);
create index if not exists pipelines_created_by_idx on public.pipelines(created_by);
create index if not exists platform_admins_created_by_idx on public.platform_admins(created_by);
create index if not exists products_created_by_idx on public.products(created_by);
create index if not exists quote_items_org_unit_fk_idx on public.quote_items(organization_id, unit_id);
create index if not exists quote_requests_org_unit_fk_idx on public.quote_requests(organization_id, unit_id);
create index if not exists quotes_created_by_idx on public.quotes(created_by);
create index if not exists services_created_by_idx on public.services(created_by);
create index if not exists site_configs_created_by_idx on public.site_configs(created_by);
create index if not exists tasks_created_by_idx on public.tasks(created_by);
create index if not exists webhook_endpoints_created_by_idx on public.webhook_endpoints(created_by);
