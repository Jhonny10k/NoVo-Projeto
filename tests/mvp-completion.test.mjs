import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(path, import.meta.url), "utf8");

test("entitlements são validados no banco e não apenas escondidos no frontend", async () => {
  const sql = await read("../supabase/migrations/202608150007_entitlements_trial_site_blocks.sql");
  const helper = await read("../src/lib/plans/entitlements.ts");
  assert.match(sql, /add column if not exists entitlements jsonb/i);
  assert.match(sql, /create or replace function public\.has_feature/i);
  assert.match(sql, /public\.has_feature\(organization_id, ''crm''\)/i);
  assert.match(sql, /public\.has_feature\(organization_id, ''quotes''\)/i);
  assert.match(sql, /public\.has_feature\(organization_id, ''tasks''\)/i);
  assert.match(helper, /requireFeature/);
});

test("trial é configurável e não bloqueia contratação paga durante o período gratuito", async () => {
  const sql = await read("../supabase/migrations/202608150007_entitlements_trial_site_blocks.sql");
  const billing = await read("../src/features/billing/actions.ts");
  assert.match(sql, /trial_days integer not null default 7/i);
  assert.match(sql, /organizations_initialize_trial/i);
  assert.match(sql, /status, trial_ends_at/i);
  assert.equal(/\["trial",\s*"active",\s*"past_due",\s*"suspended"\]/.test(billing), false);
});

test("recuperação de senha usa fluxo oficial, resposta genérica e rate limit", async () => {
  const auth = await read("../src/features/auth/actions.ts");
  const page = await read("../src/app/esqueci-senha/page.tsx");
  assert.match(auth, /resetPasswordForEmail/);
  assert.match(auth, /auth_password_reset/);
  assert.match(auth, /updateUser\(\{ password \}\)/);
  assert.match(auth, /signOut\(\)/);
  assert.match(page, /Se o e-mail estiver cadastrado/i);
});

test("editor mantém rascunho separado do snapshot publicado", async () => {
  const sql = await read("../supabase/migrations/202608150007_entitlements_trial_site_blocks.sql");
  const actions = await read("../src/features/site/actions.ts");
  const page = await read("../src/app/site/page.tsx");
  assert.match(sql, /published_snapshot jsonb/i);
  assert.match(sql, /create or replace function public\.publish_site_snapshot/i);
  assert.match(sql, /v_snapshot->'sections'/i);
  assert.match(actions, /move_site_section/);
  assert.match(page, /DevicePreview/);
  assert.match(page, /Publicar alterações/);
});

test("site e formulários públicos respeitam assinatura ou trial válido", async () => {
  const sql = await read("../supabase/migrations/202608150007_entitlements_trial_site_blocks.sql");
  assert.match(sql, /organization_has_entitlement/i);
  assert.match(sql, /get_public_site[\s\S]*organization_has_entitlement\(v_org\.id,'site'\)/i);
  assert.match(sql, /quote_requests_entitlement_guard/i);
  assert.match(sql, /'forms'/i);
  assert.match(sql, /revoke all on function public\.organization_has_entitlement/i);
});

test("exportações CSV exigem entitlement e neutralizam fórmulas", async () => {
  const route = await read("../src/app/api/export/[entity]/route.ts");
  assert.match(route, /p_feature:\s*"exports"/);
  assert.match(route, /canExport !== true/);
  assert.match(route, /\^\[=\+\\-@\\t\\r\]/);
  assert.match(route, /Cache-Control":"private, no-store"/);
  assert.match(route, /limit\(10000\)/);
});

test("admin consegue configurar entitlements e trial dos planos", async () => {
  const sql = await read("../supabase/migrations/202608150007_entitlements_trial_site_blocks.sql");
  const action = await read("../src/features/admin/actions.ts");
  assert.match(sql, /admin_update_plan_entitlements/i);
  assert.match(sql, /is_platform_admin/i);
  assert.match(action, /featureCodes\.map/);
  assert.match(action, /p_trial_days/);
});

test("SEO público usa metadata dinâmica, JSON-LD e sitemap de sites publicados", async () => {
  const page = await read("../src/app/empresa/[slug]/page.tsx");
  const sitemap = await read("../src/app/sitemap.ts");
  const sql = await read("../supabase/migrations/202608150008_seo_contact.sql");
  assert.match(page, /generateMetadata/);
  assert.match(page, /application\/ld\+json/);
  assert.match(page, /LocalBusiness/);
  assert.match(sql, /create or replace function public\.list_public_sites/i);
  assert.match(sitemap, /list_public_sites/);
});

test("contato comercial é persistido de verdade e protegido por rate limit", async () => {
  const sql = await read("../supabase/migrations/202608150008_seo_contact.sql");
  const action = await read("../src/features/contact/actions.ts");
  assert.match(sql, /create table public\.platform_contact_messages/i);
  assert.equal(/for insert to anon|for insert to authenticated/i.test(sql), false);
  assert.match(action, /public_commercial_contact/);
  assert.match(action, /platform_contact_messages/);
  assert.match(action, /createAdminClient/);
});

test("dashboard Hoje usa timezone e comparação de períodos calculados no banco", async () => {
  const sql = await read("../supabase/migrations/202608150009_dashboard_timezone.sql");
  const page = await read("../src/app/dashboard/page.tsx");
  assert.match(sql, /timezone text not null default 'America\/Sao_Paulo'/i);
  assert.match(sql, /organization_dashboard_summary/i);
  assert.match(sql, /leads_previous_month/i);
  assert.match(sql, /followups_due/i);
  assert.match(page, /leadDelta/);
  assert.match(page, /Tarefas atrasadas/);
});

test("etapas do CRM podem ser renomeadas e reordenadas sem alterar chaves internas", async () => {
  const actions = await read("../src/features/crm/actions.ts");
  const page = await read("../src/app/crm/page.tsx");
  assert.match(actions, /updatePipelineStageAction/);
  assert.match(actions, /\["owner","admin"\]/);
  assert.match(actions, /name, sort_order:sortOrder/);
  assert.equal(/stage_key\s*:/.test(actions.slice(actions.indexOf("updatePipelineStageAction"))), false);
  assert.match(page, /Configurar etapas do funil/);
});

test("follow-up usa timezone da organização, RPC segura e registra histórico", async () => {
  const sql = await read("../supabase/migrations/202608150009_dashboard_timezone.sql");
  const actions = await read("../src/features/crm/actions.ts");
  const page = await read("../src/app/crm/[id]/page.tsx");
  assert.match(sql, /create or replace function public\.schedule_lead_followup/i);
  assert.match(sql, /p_local_datetime::timestamp at time zone v_tz/i);
  assert.match(sql, /not public\.has_feature\(p_organization_id,'crm'\)/i);
  assert.match(sql, /'follow_up_scheduled'/i);
  assert.match(sql, /revoke all on function public\.schedule_lead_followup/i);
  assert.match(actions, /rpc\("schedule_lead_followup"/);
  assert.match(page, /type="datetime-local"/);
  assert.match(page, /Agendar retorno/);
});
