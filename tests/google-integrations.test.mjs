import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const read=(p)=>readFile(new URL(p,import.meta.url),"utf8");

test("Google Calendar connection expands provider metadata but keeps OAuth state and tokens server-only",async()=>{
  const sql=await read("../supabase/migrations/202608150021_google_integrations.sql");
  const calendar=await read("../src/lib/integrations/google-calendar.ts");
  const callback=await read("../src/app/api/integrations/google-calendar/callback/route.ts");
  assert.match(sql,/provider in \('whatsapp_cloud','google_calendar'\)/i);
  assert.match(sql,/create table public\.oauth_states/i);
  assert.doesNotMatch(sql,/create policy[^;]*oauth_states/is);
  assert.match(calendar,/https:\/\/www\.googleapis\.com\/auth\/calendar\.events/);
  assert.match(calendar,/access_type","offline/);
  assert.match(calendar,/grant_type:"refresh_token"/);
  assert.match(callback,/encryptIntegrationSecret\(JSON\.stringify\(bundle\)\)/);
  assert.doesNotMatch(callback,/NEXT_PUBLIC_GOOGLE_OAUTH/);
});

test("appointment events enqueue Google Calendar work without HTTP in database triggers",async()=>{
  const sql=await read("../supabase/migrations/202608150021_google_integrations.sql");
  assert.match(sql,/events_enqueue_google_calendar/i);
  assert.match(sql,/calendar_upsert_appointment/);
  assert.match(sql,/calendar_delete_appointment/);
  assert.match(sql,/external_outbox/);
  assert.doesNotMatch(sql,/http_post|net\.http|fetch\(/i);
});

test("Google Calendar uses deterministic event ids and never sends attendee updates implicitly",async()=>{
  const calendar=await read("../src/lib/integrations/google-calendar.ts");
  const worker=await read("../src/lib/outbox/worker.ts");
  assert.match(calendar,/`saas\$\{appointmentId\.replace\(/);
  assert.match(calendar,/sendUpdates=none/);
  assert.match(calendar,/response\.status===409/);
  assert.match(calendar,/appointment_external_events/);
  assert.match(worker,/google_calendar/);
  assert.match(worker,/upsertGoogleCalendarAppointment/);
  assert.match(worker,/deleteGoogleCalendarAppointment/);
});

test("Google Maps geocoding v4 is server-side with field masks and no public API key",async()=>{
  const maps=await read("../src/lib/integrations/google-maps.ts");
  const env=await read("../.env.example");
  const site=await read("../src/components/site/site-renderer.tsx");
  assert.match(maps,/https:\/\/geocode\.googleapis\.com\/v4\/geocode\/address/);
  assert.match(maps,/"X-Goog-Api-Key":key/);
  assert.match(maps,/"X-Goog-FieldMask"/);
  assert.match(env,/^GOOGLE_MAPS_API_KEY=$/m);
  assert.doesNotMatch(env,/NEXT_PUBLIC_GOOGLE_MAPS_API_KEY/);
  assert.doesNotMatch(site,/GOOGLE_MAPS_API_KEY/);
  assert.match(site,/google\.com\/maps\/search/);
});

test("Google Calendar connection queues a future-appointment backfill without direct provider calls",async()=>{
  const sql=await read("../supabase/migrations/202608150022_google_calendar_backfill.sql");
  const callback=await read("../src/app/api/integrations/google-calendar/callback/route.ts");
  assert.match(sql,/service_enqueue_google_calendar_backfill/);
  assert.match(sql,/a\.status in \('scheduled','confirmed'\)/);
  assert.match(sql,/a\.ends_at>now\(\)/);
  assert.match(sql,/on conflict\(dedupe_key\) do nothing/i);
  assert.doesNotMatch(sql,/http_post|net\.http|fetch\(/i);
  assert.match(callback,/service_enqueue_google_calendar_backfill/);
  assert.match(callback,/initial_sync_queued/);
});

test("Google Calendar dead letters mark existing external mappings as error",async()=>{
  const worker=await read("../src/lib/outbox/worker.ts");
  assert.match(worker,/failureStatus==="dead_letter"/);
  assert.match(worker,/appointment_external_events/);
  assert.match(worker,/status:"error"/);
  assert.match(worker,/last_error:message/);
});

test("Google Calendar only becomes active after the encrypted token is persisted",async()=>{
  const callback=await read("../src/app/api/integrations/google-calendar/callback/route.ts");
  const configured=callback.indexOf('provider:"google_calendar",status:"configured"');
  const secret=callback.indexOf('from("integration_secrets").upsert');
  const active=callback.indexOf('status:"active"');
  assert.ok(configured>=0);
  assert.ok(secret>configured);
  assert.ok(active>secret);
  assert.match(callback,/status:"error",last_error:"GOOGLE_SECRET_SAVE"/);
});


test("Google Calendar prunes expired OAuth states before starting a new authorization",async()=>{
  const start=await read("../src/app/api/integrations/google-calendar/start/route.ts");
  assert.match(start,/oauth_states"\)\.delete\(\)\.lt\("expires_at"/);
  assert.match(start,/10\*60\*1000/);
});
