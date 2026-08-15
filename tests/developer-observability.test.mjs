import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const read=p=>readFile(new URL(p,import.meta.url),"utf8");

test("OpenAPI v1 is versioned, documents real routes and never embeds tenant credentials",async()=>{
  const spec=await read("../src/lib/public-api/openapi.ts");
  const route=await read("../src/app/api/v1/openapi.json/route.ts");
  assert.match(spec,/openapi:"3\.1\.1"/);
  assert.match(spec,/version:"1\.0\.0"/);
  assert.match(spec,/"\/api\/v1\/leads"/);
  assert.match(spec,/"\/api\/v1\/customers"/);
  assert.match(spec,/"\/api\/v1\/quotes"/);
  assert.match(spec,/"x-required-scope":"leads:write"/);
  assert.match(spec,/bearerAuth/);
  assert.doesNotMatch(spec,/nd_live_[A-Za-z0-9_-]{20,}/);
  assert.match(route,/publicApiOpenApiDocument/);
  assert.match(route,/Cache-Control/);
});

test("API operational logs expose metadata only through privileged RPC",async()=>{
  const sql=await read("../supabase/migrations/202608150028_developer_observability.sql");
  const page=await read("../src/app/desenvolvedores/page.tsx");
  assert.match(sql,/create or replace function public\.list_api_request_logs/i);
  assert.match(sql,/has_org_role\(p_organization_id,array\['owner','admin'\]\)/i);
  assert.match(sql,/key_prefix/);
  const rpc=sql.slice(sql.indexOf("create or replace function public.list_api_request_logs"),sql.indexOf("create or replace function public.retry_webhook_delivery"));assert.doesNotMatch(rpc,/authorization|request_body|response_body|ip_address|secret_hash\s+as/i);
  assert.match(page,/list_api_request_logs/);
  assert.match(page,/Corpo, Authorization, IP, chave completa/);
});

test("manual webhook retry reuses the existing dead-letter job and is audited",async()=>{
  const sql=await read("../supabase/migrations/202608150028_developer_observability.sql");
  const actions=await read("../src/features/developer/actions.ts");
  const page=await read("../src/app/desenvolvedores/page.tsx");
  assert.match(sql,/create or replace function public\.retry_webhook_delivery/i);
  assert.match(sql,/v_delivery\.status<>'failed'/i);
  assert.match(sql,/v_job\.status<>'dead_letter'/i);
  assert.match(sql,/update public\.external_outbox\s+set status='pending',attempts=0/is);
  assert.match(sql,/webhook_delivery\.manual_retry/);
  assert.doesNotMatch(sql,/insert into public\.external_outbox[\s\S]*webhook_delivery\.manual_retry/i);
  assert.match(actions,/retry_webhook_delivery/);
  assert.match(actions,/createClient\(\)/);
  assert.match(page,/item\.status==="failed"/);
  assert.match(page,/Reenfileirar/);
});
