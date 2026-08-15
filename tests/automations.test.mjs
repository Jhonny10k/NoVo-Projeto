import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read=(path)=>readFile(new URL(path,import.meta.url),"utf8");

test("migration chain no longer references undefined member_role enum",async()=>{
  const sql=await read("../supabase/migrations/202608150006_catalog_notifications.sql");
  assert.doesNotMatch(sql,/public\.member_role\[\]/i);
  assert.match(sql,/array\['owner','admin','sales','support'\]::text\[\]/i);
});

test("automations are plan-gated and tenant-isolated",async()=>{
  const sql=await read("../supabase/migrations/202608150012_automations_v1.sql");
  const entitlements=await read("../src/lib/plans/entitlements.ts");
  assert.match(sql,/\{"automations":true\}/i);
  assert.match(sql,/alter table public\.automations enable row level security/i);
  assert.match(sql,/public\.is_org_member\(organization_id\).*public\.has_feature\(organization_id,'automations'\)/is);
  assert.match(entitlements,/"automations"/);
});

test("automation V1 only accepts internal safe actions",async()=>{
  const sql=await read("../supabase/migrations/202608150012_automations_v1.sql");
  const action=await read("../src/features/automations/actions.ts");
  assert.match(sql,/v_type not in\('create_task','add_tag','move_stage','notify_team'\)/i);
  assert.match(action,/actionType==="create_task"/);
  assert.match(action,/actionType==="add_tag"/);
  assert.match(action,/actionType==="move_stage"/);
  assert.match(action,/actionType==="notify_team"/);
  assert.doesNotMatch(sql,/v_type='send_email'|v_type='send_whatsapp'|v_type='execute_ai'/i);
});

test("automation event processing is event-driven and idempotent",async()=>{
  const sql=await read("../supabase/migrations/202608150012_automations_v1.sql");
  assert.match(sql,/unique\(automation_id,source_event_id\)/i);
  assert.match(sql,/create trigger events_process_automations[\s\S]*after insert on public\.events/i);
  assert.match(sql,/exists\(select 1 from public\.automation_runs r where r\.automation_id=v_auto\.id and r\.source_event_id=new\.id\)/i);
  assert.match(sql,/on conflict\(automation_id,source_event_id\) do nothing/i);
});

test("automation conditions and internal actions operate on real domain data",async()=>{
  const sql=await read("../supabase/migrations/202608150012_automations_v1.sql");
  for(const condition of ["source","status","tag","min_value_cents"]) assert.match(sql,new RegExp(`v_conditions \\? '${condition}'`,'i'));
  assert.match(sql,/insert into public\.tasks/i);
  assert.match(sql,/update public\.leads set tags=/i);
  assert.match(sql,/update public\.leads set stage_id=/i);
  assert.match(sql,/insert into public\.notifications/i);
});

test("automation executions preserve executed failed ignored and dry-run logs",async()=>{
  const sql=await read("../supabase/migrations/202608150012_automations_v1.sql");
  assert.match(sql,/status in \('executed','failed','ignored','dry_run'\)/i);
  assert.match(sql,/Configuração validada; nenhuma ação foi executada\./i);
  assert.match(sql,/jsonb_build_object\('run_id',v_run[\s\S]*'executed',false\)/i);
  assert.match(sql,/v_status:=case when v_failed then 'failed' else 'executed' end/i);
});

test("automations page explicitly communicates provider boundaries",async()=>{
  const page=await read("../src/app/automacoes/page.tsx");
  assert.match(page,/E-mail, WhatsApp e IA não aparecem como disponíveis enquanto não houver integração real\./i);
  assert.match(page,/Testar sem executar/i);
  assert.match(page,/Execuções recentes/i);
});

test("automation condition JSON is validated and malformed numeric conditions cannot abort domain events",async()=>{
  const sql=await read("../supabase/migrations/202608150012_automations_v1.sql");
  assert.match(sql,/v_condition_key not in\('source','status','tag','min_value_cents'\)/i);
  assert.match(sql,/jsonb_typeof\(p_conditions->'min_value_cents'\)<>'number'/i);
  assert.match(sql,/exception when others then\s*v_match:=false; v_reason:='invalid minimum value condition'/i);
});
