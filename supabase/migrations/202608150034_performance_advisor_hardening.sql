-- 2026-08-15 — Ajustes objetivos apontados pelo Supabase Performance Advisor.
-- Não removemos índices 'unused' em banco recém-criado: ainda não existe carga real para medir uso.

-- Evita reavaliar auth.uid() por linha nas policies sinalizadas.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists platform_admins_select_self on public.platform_admins;
create policy platform_admins_select_self on public.platform_admins
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications
  for select to authenticated
  using (user_id = (select auth.uid()) and public.is_org_member(organization_id));

drop policy if exists organization_member_units_select on public.organization_member_units;
create policy organization_member_units_select on public.organization_member_units
  for select to authenticated
  using (
    public.has_feature(organization_id,'multi_unit')
    and (user_id = (select auth.uid()) or public.has_org_role(organization_id,array['owner','admin']))
  );

drop policy if exists events_insert_staff on public.events;
create policy events_insert_staff on public.events
  for insert to authenticated
  with check (
    public.has_org_role(organization_id,array['owner','admin','sales','support'])
    and actor_user_id = (select auth.uid())
    and event_type in ('lead_created','lead_stage_changed','note_added','task_completed')
    and public.can_access_unit_scope(organization_id,unit_id)
  );

-- FKs mais usadas em joins, deleções/cascatas e filtros operacionais.
create index if not exists appointments_customer_idx on public.appointments(customer_id) where customer_id is not null;
create index if not exists appointments_lead_idx on public.appointments(lead_id) where lead_id is not null;
create index if not exists appointments_service_idx on public.appointments(service_id) where service_id is not null;
create index if not exists appointment_external_events_org_idx on public.appointment_external_events(organization_id);
create index if not exists audit_logs_org_idx on public.audit_logs(organization_id) where organization_id is not null;
create index if not exists automation_runs_source_event_idx on public.automation_runs(source_event_id) where source_event_id is not null;
create index if not exists billing_checkout_plan_idx on public.billing_checkout_sessions(plan_id);
create index if not exists billing_checkout_coupon_idx on public.billing_checkout_sessions(coupon_id) where coupon_id is not null;
create index if not exists billing_webhook_org_idx on public.billing_webhook_events(organization_id) where organization_id is not null;
create index if not exists communication_messages_lead_fk_idx on public.communication_messages(lead_id) where lead_id is not null;
create index if not exists communication_messages_customer_fk_idx on public.communication_messages(customer_id) where customer_id is not null;
create index if not exists coupon_redemptions_org_idx on public.coupon_redemptions(organization_id);
create index if not exists customers_source_lead_idx on public.customers(source_lead_id) where source_lead_id is not null;
create index if not exists external_outbox_source_event_idx on public.external_outbox(source_event_id) where source_event_id is not null;
create index if not exists leads_pipeline_idx on public.leads(pipeline_id) where pipeline_id is not null;
create index if not exists leads_stage_idx on public.leads(stage_id) where stage_id is not null;
create index if not exists leads_responsible_idx on public.leads(responsible_user_id) where responsible_user_id is not null;
create index if not exists notifications_org_idx on public.notifications(organization_id);
create index if not exists oauth_states_org_idx on public.oauth_states(organization_id);
create index if not exists oauth_states_user_idx on public.oauth_states(user_id);
create index if not exists pipeline_stages_org_idx on public.pipeline_stages(organization_id);
create index if not exists pipelines_org_fk_idx on public.pipelines(organization_id);
create index if not exists products_category_idx on public.products(category_id) where category_id is not null;
create index if not exists services_category_idx on public.services(category_id) where category_id is not null;
create index if not exists quote_items_quote_idx on public.quote_items(quote_id);
create index if not exists quote_requests_lead_idx on public.quote_requests(lead_id);
create index if not exists quotes_customer_idx on public.quotes(customer_id) where customer_id is not null;
create index if not exists quotes_lead_idx on public.quotes(lead_id) where lead_id is not null;
create index if not exists site_sections_org_idx on public.site_sections(organization_id);
create index if not exists subscriptions_org_idx on public.subscriptions(organization_id);
create index if not exists subscriptions_plan_idx on public.subscriptions(plan_id);
create index if not exists tasks_assigned_idx on public.tasks(assigned_to) where assigned_to is not null;
create index if not exists tasks_customer_idx on public.tasks(customer_id) where customer_id is not null;
create index if not exists tasks_lead_idx on public.tasks(lead_id) where lead_id is not null;
create index if not exists webhook_deliveries_event_idx on public.webhook_deliveries(event_id);
