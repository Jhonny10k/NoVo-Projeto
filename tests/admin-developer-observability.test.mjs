import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const read=p=>readFile(new URL(p,import.meta.url),"utf8");

test("admin developer observability is platform-admin only and aggregated",async()=>{
  const sql=await read("../supabase/migrations/202608150030_admin_developer_observability.sql");
  assert.match(sql,/admin_developer_observability/i);
  assert.match(sql,/not public\.is_platform_admin\(\)/i);
  assert.match(sql,/top_routes/i);
  assert.match(sql,/top_organizations/i);
  assert.match(sql,/dead_letter/i);
  const body=sql.slice(sql.indexOf("create or replace function public.admin_developer_observability"));
  assert.doesNotMatch(body,/request_body|response_body|authorization|secret_hash|ciphertext|auth_tag|\bpayload\b/i);
});

test("admin page consumes the aggregated developer health RPC without exposing payloads",async()=>{
  const page=await read("../src/app/admin/page.tsx");
  assert.match(page,/admin_developer_observability/);
  assert.match(page,/Saúde da API e integrações/);
  assert.match(page,/Dead letters/);
  assert.match(page,/sem payloads, credenciais ou corpos/i);
  assert.doesNotMatch(page,/request_body|response_body|authorization|ciphertext|auth_tag/i);
});
