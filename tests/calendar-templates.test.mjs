import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const read=(path)=>readFile(new URL(path,import.meta.url),"utf8");

test("calendar RPC resolves day week and month in organization timezone",async()=>{
  const sql=await read("../supabase/migrations/202608150015_calendar_templates.sql");const page=await read("../src/app/agenda/calendario/page.tsx");
  assert.match(sql,/appointments_calendar/i);assert.match(sql,/v_view not in\('day','week','month'\)/i);assert.match(sql,/at time zone v_tz/i);assert.match(sql,/public\.has_feature\(p_organization_id,'appointments'\)/i);assert.match(page,/Dia/);assert.match(page,/Semana/);assert.match(page,/Mês/);
});

test("calendar only returns appointments from the current tenant and requested interval",async()=>{
  const sql=await read("../supabase/migrations/202608150015_calendar_templates.sql");
  assert.match(sql,/a\.organization_id=p_organization_id and a\.starts_at<v_end and a\.ends_at>v_start/i);assert.match(sql,/public\.is_org_member\(p_organization_id\)/i);
});

test("five initial site templates exist and use only supported blocks",async()=>{
  const templates=await read("../src/lib/site/templates.ts");
  for(const key of ["oficina","agricola","loja","restaurante","servicos"])assert.match(templates,new RegExp(`key:\"${key}\"`));
  assert.match(templates,/type:\"hero\"/);assert.match(templates,/type:\"about\"/);assert.match(templates,/type:\"services\"/);assert.match(templates,/type:\"products\"/);assert.match(templates,/type:\"contact\"/);assert.match(templates,/type:\"cta\"/);
});

test("template application is transactional, admin-controlled and never publishes automatically",async()=>{
  const sql=await read("../supabase/migrations/202608150015_calendar_templates.sql");const action=await read("../src/features/site/actions.ts");
  assert.match(sql,/apply_site_template/i);assert.match(sql,/has_org_role\(p_organization_id,array\['owner','admin'\]\)/i);assert.match(sql,/update public\.site_sections/i);assert.match(sql,/site\.template_applied/i);assert.doesNotMatch(sql,/published_snapshot\s*=/i);assert.match(action,/applySiteTemplateAction/);
});
