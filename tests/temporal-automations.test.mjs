import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration=await readFile(new URL("../supabase/migrations/202608150017_temporal_automations.sql",import.meta.url),"utf8");
const actions=await readFile(new URL("../src/features/automations/actions.ts",import.meta.url),"utf8");
const page=await readFile(new URL("../src/app/automacoes/page.tsx",import.meta.url),"utf8");
const scheduler=await readFile(new URL("../docs/SCHEDULER.md",import.meta.url),"utf8");

test("temporal automation triggers are validated in the database",()=>{
  assert.match(migration,/lead_no_response/);
  assert.match(migration,/customer_inactive/);
  assert.match(migration,/date_specific/);
  assert.match(migration,/after_minutes.*15.*525600/is);
  assert.match(migration,/inactive_days.*1.*3650/is);
  assert.match(migration,/scheduled date must be in the future/i);
});

test("temporal runs are concurrency-safe and idempotent",()=>{
  assert.match(migration,/pg_try_advisory_xact_lock/i);
  assert.match(migration,/dedupe_key text/i);
  assert.match(migration,/unique index[\s\S]*automation_id,dedupe_key/i);
  assert.match(migration,/on conflict \(automation_id,dedupe_key\)/i);
});

test("temporal worker is private to backend/service role",()=>{
  assert.match(migration,/revoke all on function public\.run_temporal_automations[\s\S]*public, anon, authenticated/i);
  assert.match(migration,/grant execute on function public\.run_temporal_automations[\s\S]*service_role/i);
});

test("date-specific and customer-inactive automations cannot require lead context",()=>{
  assert.match(migration,/p_trigger_event in\('customer_inactive','date_specific'\)[\s\S]*v_type in\('add_tag','move_stage'\)/i);
});

test("UI and server actions match the real Supabase Cron schedule",()=>{
  assert.match(actions,/condition_after_minutes/);
  assert.match(actions,/condition_inactive_days/);
  assert.match(actions,/condition_run_at_local/);
  assert.match(page,/Supabase Cron/);
  assert.match(scheduler,/\*\/5 \* \* \* \*/);
  assert.match(scheduler,/run_temporal_automations/);
});
