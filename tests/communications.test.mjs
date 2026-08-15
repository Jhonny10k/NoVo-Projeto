import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(path, import.meta.url), "utf8");

test("communication secrets are isolated from tenant-readable connection metadata", async () => {
  const sql = await read("../supabase/migrations/202608150018_communications_phase3.sql");
  assert.match(sql, /create table public\.integration_secrets/i);
  assert.match(sql, /alter table public\.integration_secrets enable row level security/i);
  assert.doesNotMatch(sql, /create policy[^;]*integration_secrets/is);
  const actions = await read("../src/features/integrations/actions.ts");
  assert.match(actions, /config:\{phone_number_id:phoneNumberId,waba_id:wabaId\}/);
  assert.match(actions, /encryptIntegrationSecret\(token\)/);
  assert.match(actions, /integration_secrets/);
  assert.doesNotMatch(actions, /config:\{[^}]*access_token/s);
});

test("integration secret encryption uses AES-256-GCM and a server-only 32-byte key", async () => {
  const box = await read("../src/lib/communications/secret-box.ts");
  const env = await read("../.env.example");
  assert.match(box, /aes-256-gcm/);
  assert.match(box, /randomBytes\(12\)/);
  assert.match(box, /getAuthTag/);
  assert.match(box, /key\.length!==32/);
  assert.match(env, /^INTEGRATION_ENCRYPTION_KEY=$/m);
  assert.doesNotMatch(env, /NEXT_PUBLIC_INTEGRATION_ENCRYPTION_KEY/);
});

test("Resend delivery uses HTTP API with an idempotency key and no fake success", async () => {
  const email = await read("../src/lib/communications/email.ts");
  const actions = await read("../src/features/communications/actions.ts");
  assert.match(email, /https:\/\/api\.resend\.com\/emails/);
  assert.match(email, /"Idempotency-Key":input\.idempotencyKey/);
  assert.match(email, /if\(!response\.ok\|\|typeof body\?\.id!=="string"\)throw/);
  assert.match(actions, /status:"queued"/);
  assert.match(actions, /status:"sent",sent_at:/);
  assert.match(actions, /status:"failed",error_message:/);
});

test("WhatsApp Cloud API requires a configured graph version and real provider verification", async () => {
  const wa = await read("../src/lib/communications/whatsapp.ts");
  const actions = await read("../src/features/integrations/actions.ts");
  assert.match(wa, /META_GRAPH_API_VERSION/);
  assert.doesNotMatch(wa, /process\.env\.META_GRAPH_API_VERSION\|\|"v\d+/);
  assert.match(wa, /graph\.facebook\.com/);
  assert.match(wa, /display_phone_number,verified_name,quality_rating/);
  assert.match(actions, /verified=await verifyWhatsAppConnection\(organization\.id\)/);
  assert.match(actions, /status:"active",last_verified_at:/);
});

test("free-form WhatsApp is blocked outside the inbound service window while templates remain explicit", async () => {
  const actions = await read("../src/features/communications/actions.ts");
  const page = await read("../src/app/crm/[id]/page.tsx");
  assert.match(actions, /Date\.now\(\)-24\*60\*60\*1000/);
  assert.match(actions, /eq\("direction","inbound"\)/);
  assert.match(actions, /if\(!inbound\?\.length\)redirect\(`\/crm\/\$\{leadId\}\?erro=whatsapp_janela`\)/);
  assert.match(actions, /sendWhatsAppTemplate/);
  assert.match(page, /template já aprovado na Meta/);
});

test("WhatsApp webhook authenticates the raw request before parsing and only service-role RPCs mutate data", async () => {
  const route = await read("../src/app/api/webhooks/whatsapp/route.ts");
  const sql = await read("../supabase/migrations/202608150018_communications_phase3.sql");
  assert.match(route, /x-hub-signature-256/);
  assert.match(route, /createHmac\("sha256"/);
  assert.match(route, /timingSafeEqual/);
  const signaturePos = route.indexOf("verifySignature");
  const parsePos = route.indexOf("JSON.parse", signaturePos);
  assert.ok(signaturePos >= 0 && parsePos > signaturePos, "signature must be checked before JSON processing");
  assert.match(route, /service_record_whatsapp_inbound/);
  assert.match(route, /service_update_communication_status/);
  assert.match(sql, /grant execute on function public\.service_record_whatsapp_inbound[\s\S]*to service_role/i);
  assert.match(sql, /grant execute on function public\.service_update_communication_status[\s\S]*to service_role/i);
});

test("inbound WhatsApp is idempotent and creates a real lead only for an active tenant connection", async () => {
  const sql = await read("../supabase/migrations/202608150018_communications_phase3.sql");
  assert.match(sql, /unique index communication_messages_provider_id_uidx/i);
  assert.match(sql, /on conflict \(provider,provider_message_id\)[\s\S]*do nothing/i);
  assert.match(sql, /insert into public\.leads[\s\S]*'whatsapp','new'/i);
  assert.match(sql, /provider='whatsapp_cloud' and status='active'/i);
  assert.match(sql, /'whatsapp_message_received'/i);
});

test("integration UI never returns or pre-fills the WhatsApp access token", async () => {
  const page = await read("../src/app/integracoes/page.tsx");
  assert.match(page, /type="password"/);
  assert.match(page, /Deixe vazio para manter o token atual/);
  assert.match(page, /nunca volta para o navegador/);
  assert.doesNotMatch(page, /defaultValue=\{current\?\.config\?\.access_token/);
});
