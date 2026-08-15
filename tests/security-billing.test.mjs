import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(path, import.meta.url), "utf8");

test("rate limiting persistente usa RPC reservada ao backend", async () => {
  const sql = await read("../supabase/migrations/202608150004_security_team_storage.sql");
  assert.match(sql, /create table public\.rate_limit_windows/i);
  assert.match(sql, /create or replace function public\.consume_rate_limit/i);
  assert.match(sql, /grant execute on function public\.consume_rate_limit[^;]+to service_role/i);
  assert.equal(/grant execute on function public\.consume_rate_limit[^;]+to authenticated/i.test(sql), false);
});

test("gestão de equipe protege o último proprietário e usa convite server-side", async () => {
  const sql = await read("../supabase/migrations/202608150004_security_team_storage.sql");
  const actions = await read("../src/features/team/actions.ts");
  assert.match(sql, /last owner|último proprietário|last_owner|cannot remove.*owner|owner_count/is);
  assert.match(actions, /admin\.auth\.admin\.inviteUserByEmail/);
  assert.match(actions, /actor_user_id:\s*user\.id/);
});

test("storage restringe bucket público a imagens pequenas e escrita por tenant", async () => {
  const sql = await read("../supabase/migrations/202608150004_security_team_storage.sql");
  assert.match(sql, /organization-assets/);
  assert.match(sql, /file_size_limit[\s\S]{0,120}5242880/i);
  assert.match(sql, /image\/jpeg/);
  assert.match(sql, /image\/png/);
  assert.match(sql, /image\/webp/);
  assert.match(sql, /storage\.objects/i);
  assert.match(sql, /organization_id|split_part\(name/i);
});

test("billing cria checkout real, valida webhook e não ativa assinatura por suposição", async () => {
  const provider = await read("../src/lib/billing/mercadopago.ts");
  const webhook = await read("../src/app/api/billing/mercadopago/webhook/route.ts");
  const sync = await read("../src/lib/billing/sync.ts");
  assert.match(provider, /api\.mercadopago\.com[\s\S]*?\/preapproval/);
  assert.match(provider, /status:\s*"pending"/);
  assert.match(webhook, /WebhookSignatureValidator/);
  assert.match(webhook, /billing_webhook_events/);
  assert.match(sync, /normalizedStatus === "authorized"[\s\S]*?"active"/);
  assert.equal(/status:\s*"active"/.test(provider), false);
});

test("billing persiste valor contratado e MRR não depende apenas do preço atual do plano", async () => {
  const sql = await read("../supabase/migrations/202608150005_billing_mercadopago.sql");
  const sync = await read("../src/lib/billing/sync.ts");
  assert.match(sql, /subscriptions[\s\S]*add column amount_cents/i);
  assert.match(sql, /coalesce\(s\.amount_cents, p\.price_monthly_cents\)/i);
  assert.match(sync, /amount_cents:\s*Number\(session\.amount_cents\)/);
});

test("segredos de billing, rate limit e Supabase continuam somente no servidor", async () => {
  const env = await read("../.env.example");
  assert.match(env, /^SUPABASE_SECRET_KEY=/m);
  assert.match(env, /^MERCADO_PAGO_ACCESS_TOKEN=/m);
  assert.match(env, /^MERCADO_PAGO_WEBHOOK_SECRET=/m);
  assert.match(env, /^RATE_LIMIT_SALT=/m);
  assert.equal(/NEXT_PUBLIC_(SUPABASE_SECRET_KEY|MERCADO_PAGO_ACCESS_TOKEN|MERCADO_PAGO_WEBHOOK_SECRET|RATE_LIMIT_SALT)/.test(env), false);
});

test("categorias têm unicidade por tenant e vínculo é validado antes de salvar catálogo", async () => {
  const sql = await read("../supabase/migrations/202608150006_catalog_notifications.sql");
  const actions = await read("../src/features/catalog/actions.ts");
  assert.match(sql, /categories_org_lower_name_uidx/);
  assert.match(sql, /organization_id, lower\(name\)/i);
  assert.match(actions, /categoryIdForTenant/);
  assert.match(actions, /eq\("organization_id", organizationId\)/);
});

test("notificações são individuais por usuário e derivadas de eventos reais", async () => {
  const sql = await read("../supabase/migrations/202608150006_catalog_notifications.sql");
  assert.match(sql, /create table public\.notifications/i);
  assert.match(sql, /user_id uuid not null/i);
  assert.match(sql, /unique \(source_event_id, user_id\)/i);
  assert.match(sql, /create trigger events_fanout_notification/i);
  assert.match(sql, /user_id = auth\.uid\(\)/i);
});

test("timeline existe para lead e cliente sem consulta fora do tenant", async () => {
  const leadPage = await read("../src/app/crm/[id]/page.tsx");
  const customerPage = await read("../src/app/clientes/[id]/page.tsx");
  assert.match(leadPage, /eq\("organization_id", organization\.id\)/);
  assert.match(customerPage, /eq\("organization_id", organization\.id\)/);
  assert.match(leadPage, /EventTimeline/);
  assert.match(customerPage, /EventTimeline/);
});

test("superfícies de autenticação e resposta pública usam rate limit", async () => {
  const auth = await read("../src/features/auth/actions.ts");
  const quote = await read("../src/features/quotes/actions.ts");
  assert.match(auth, /auth_signin/);
  assert.match(auth, /auth_signup/);
  assert.match(quote, /public_quote_response/);
  assert.match(auth, /consumeRateLimit/);
  assert.match(quote, /consumeRateLimit/);
});


test("histórico é append-only e eventos diretos exigem ator autenticado", async () => {
  const sql = await read("../supabase/migrations/202608150006_catalog_notifications.sql");
  const crm = await read("../src/features/crm/actions.ts");
  assert.match(sql, /drop policy if exists events_update_staff/i);
  assert.match(sql, /drop policy if exists events_delete_admin/i);
  assert.match(sql, /actor_user_id = auth\.uid\(\)/i);
  assert.match(sql, /event_type in \('lead_created','lead_stage_changed','note_added','task_completed'\)/i);
  assert.match(crm, /lead_stage_changed[\s\S]{0,260}actor_user_id|actor_user_id:[\s\S]{0,260}lead_stage_changed/);
});

test("conteúdo de notificações não pode ser editado diretamente pelo cliente", async () => {
  const sql = await read("../supabase/migrations/202608150006_catalog_notifications.sql");
  assert.equal(/create policy notifications_update_own/i.test(sql), false);
  assert.match(sql, /create or replace function public\.mark_notifications_read/i);
  assert.match(sql, /grant execute on function public\.mark_notifications_read\(uuid,uuid\) to authenticated/i);
  assert.match(sql, /revoke all on function public\.fanout_event_notification\(\) from authenticated/i);
});
