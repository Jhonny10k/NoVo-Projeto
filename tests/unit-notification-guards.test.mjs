import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const read=p=>readFile(new URL(p,import.meta.url),"utf8");

test("multi-unit notification guard suppresses recipients outside the entity unit even without auth context",async()=>{
  const sql=await read("../supabase/migrations/202608150029_unit_notification_guards.sql");
  assert.match(sql,/create or replace function public\.guard_notification_unit_scope/i);
  assert.match(sql,/organization_has_entitlement\(new\.organization_id,'multi_unit'\)/i);
  assert.match(sql,/user_can_access_unit\(new\.organization_id,new\.user_id,v_unit\)/i);
  assert.match(sql,/return null;/i);
  assert.match(sql,/before insert on public\.notifications/i);
});

test("recipient-specific outbox jobs inherit the source event unit boundary",async()=>{
  const sql=await read("../supabase/migrations/202608150029_unit_notification_guards.sql");
  assert.match(sql,/create or replace function public\.guard_external_outbox_unit_recipient/i);
  assert.match(sql,/select unit_id into v_unit from public\.events/i);
  assert.match(sql,/user_can_access_unit\(new\.organization_id,new\.recipient_user_id,v_unit\)/i);
  assert.match(sql,/before insert on public\.external_outbox/i);
});

test("event fanout itself uses entitlement lookup that works for public and service-originated events",async()=>{
  const sql=await read("../supabase/migrations/202608150027_unit_scoped_commercial.sql");
  const start=sql.indexOf("create or replace function public.fanout_event_notification");
  const section=sql.slice(start);
  assert.match(section,/organization_has_entitlement\(new\.organization_id,'multi_unit'\)/i);
  assert.doesNotMatch(section,/not public\.has_feature\(new\.organization_id,'multi_unit'\)/i);
});
