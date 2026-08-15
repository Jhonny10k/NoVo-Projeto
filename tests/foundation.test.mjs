import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(path, import.meta.url), "utf8");

test("nenhum segredo de service role é declarado como variável pública", async () => {
  const env = await read("../.env.example");
  assert.equal(env.includes("NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY"), false);
});

test("migration principal ativa RLS e não remove tabelas", async () => {
  const sql = await read("../supabase/migrations/202608150001_initial_core.sql");
  assert.match(sql, /enable row level security/i);
  assert.match(sql, /organization_id/i);
  assert.equal(/drop\s+table/i.test(sql), false);
});

test("barreira multi-tenant e entrada pública de lead existem", async () => {
  const sql = await read("../supabase/migrations/202608150001_initial_core.sql");
  assert.match(sql, /create or replace function public\.is_org_member/i);
  assert.match(sql, /create or replace function public\.public_create_quote_request/i);
  assert.match(sql, /security definer/i);
});

test("orçamento comercial usa RPC transacional e resposta pública controlada", async () => {
  const sql = await read("../supabase/migrations/202608150002_commercial_core.sql");
  assert.match(sql, /create or replace function public\.create_quote_with_items/i);
  assert.match(sql, /create or replace function public\.respond_public_quote/i);
  assert.match(sql, /public_token/i);
  assert.equal(/drop\s+table/i.test(sql), false);
});

test("admin global exige platform_admin e mantém RLS", async () => {
  const sql = await read("../supabase/migrations/202608150003_platform_admin.sql");
  assert.match(sql, /platform_admins enable row level security/i);
  assert.match(sql, /not public\.is_platform_admin\(\)/i);
  assert.match(sql, /audit_logs/i);
});

test("billing desativado não finge checkout", async () => {
  const provider = await read("../src/lib/billing/provider.ts");
  assert.match(provider, /configured: false/);
  assert.match(provider, /Nenhuma cobrança será simulada/i);
});

test("demo é opt-in", async () => {
  const env = await read("../.env.example");
  assert.match(env, /DEMO_MODE=false/);
});
