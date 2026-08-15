import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(path, import.meta.url), "utf8");

test("consumo global de IA exige platform admin e não retorna prompts", async () => {
  const sql = await read("../supabase/migrations/202608150016_admin_ai_usage.sql");
  assert.match(sql, /not public\.is_platform_admin\(\)/i);
  assert.match(sql, /admin_ai_usage_summary/i);
  assert.match(sql, /organizations_using_ai/i);
  assert.match(sql, /estimated_cost_usd_micros/i);
  assert.doesNotMatch(sql, /\binput_text\b|\boutput_text\b|\bprompt\b/i);
});

test("painel master consome apenas o resumo agregado de IA", async () => {
  const page = await read("../src/app/admin/page.tsx");
  assert.match(page, /admin_ai_usage_summary/);
  assert.match(page, /Consumo de IA/);
  assert.match(page, /prompts e respostas não são expostos/i);
  assert.doesNotMatch(page, /ai_usage[^_]/i);
});
