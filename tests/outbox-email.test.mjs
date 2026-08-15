import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read=(path)=>readFile(new URL(path,import.meta.url),"utf8");

test("external outbox is server-only, deduplicated, retryable, and never performs HTTP in the trigger",async()=>{
  const sql=await read("../supabase/migrations/202608150019_transactional_outbox.sql");
  assert.match(sql,/create table public\.external_outbox/i);
  assert.match(sql,/unique\(dedupe_key\)/i);
  assert.match(sql,/for update skip locked/i);
  assert.match(sql,/dead_letter/i);
  assert.match(sql,/worker lock expired/i);
  assert.match(sql,/grant execute on function public\.service_claim_external_outbox[\s\S]*to service_role/i);
  assert.doesNotMatch(sql,/http_post|net\.http|fetch\(/i);
  assert.doesNotMatch(sql,/create policy[^;]*external_outbox/is);
});

test("system emails are queued from real organization, lead, and subscription events",async()=>{
  const sql=await read("../supabase/migrations/202608150019_transactional_outbox.sql");
  assert.match(sql,/event_type='organization_created'/i);
  assert.match(sql,/event_type='lead_created'/i);
  assert.match(sql,/event_type='subscription_status_changed'/i);
  assert.match(sql,/notification_preferences->'leads'/i);
  assert.match(sql,/notification_preferences->'billing'/i);
  assert.match(sql,/on conflict\(dedupe_key\) do nothing/i);
});

test("outbox worker uses stable provider idempotency and only marks dead letters failed",async()=>{
  const worker=await read("../src/lib/outbox/worker.ts");
  const route=await read("../src/app/api/internal/outbox/process/route.ts");
  assert.match(worker,/idempotencyKey:`outbox-\$\{job\.id\}`/);
  assert.match(worker,/service_claim_external_outbox/);
  assert.match(worker,/service_complete_external_outbox/);
  assert.match(worker,/service_fail_external_outbox/);
  assert.match(worker,/failureStatus===\"dead_letter\"/);
  assert.match(route,/OUTBOX_WORKER_SECRET/);
  assert.match(route,/timingSafeEqual/);
});

test("Resend webhook verifies raw payload before parsing and stores provider events idempotently",async()=>{
  const route=await read("../src/app/api/webhooks/resend/route.ts");
  const verifier=await read("../src/lib/communications/resend-webhook.ts");
  const sql=await read("../supabase/migrations/202608150020_resend_webhooks.sql");
  const rawPos=route.indexOf("await request.text()");
  const verifyPos=route.indexOf("verifyResendWebhook",rawPos);
  const parsePos=route.indexOf("JSON.parse",verifyPos);
  assert.ok(rawPos>=0&&verifyPos>rawPos&&parsePos>verifyPos);
  assert.match(route,/svix-id/);
  assert.match(route,/svix-timestamp/);
  assert.match(route,/svix-signature/);
  assert.match(verifier,/`\$\{id\}\.\$\{timestamp\}\.\$\{payload\}`/);
  assert.match(verifier,/createHmac\(\"sha256\"/);
  assert.match(verifier,/Math\.abs\(nowSeconds-ts\)>300/);
  assert.match(sql,/unique\(provider,provider_event_id\)/i);
  assert.match(sql,/email\.delivered/);
  assert.match(sql,/email\.bounced/);
  assert.match(sql,/status='delivered'/i);
});
