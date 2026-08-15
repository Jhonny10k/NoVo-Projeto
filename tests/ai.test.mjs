import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const read=(path)=>readFile(new URL(path,import.meta.url),"utf8");

test("AI provider is decoupled and uses server-side Responses API without persistence",async()=>{
  const provider=await read("../src/lib/ai/provider.ts");const openai=await read("../src/lib/ai/openai.ts");const env=await read("../.env.example");
  assert.match(provider,/interface AIProvider/);assert.match(openai,/\/v1\/responses/);assert.match(openai,/store:false/);assert.match(openai,/OPENAI_API_KEY/);assert.match(env,/OPENAI_API_KEY=/);assert.doesNotMatch(env,/NEXT_PUBLIC_OPENAI/);
});

test("AI usage is plan-gated, monthly-limited and persisted with tokens",async()=>{
  const sql=await read("../supabase/migrations/202608150014_ai_usage_provider.sql");
  assert.match(sql,/create table public\.ai_usage/i);assert.match(sql,/ai_requests_per_month/);assert.match(sql,/ai_tokens_per_month/);assert.match(sql,/begin_ai_usage/i);assert.match(sql,/input_tokens integer/i);assert.match(sql,/estimated_cost_usd_micros/i);assert.match(sql,/public\.has_org_role\(p_organization_id,array\['owner','admin','sales','support'\]\)/i);
});

test("AI service rate-limits requests and records success or failure server-side",async()=>{
  const service=await read("../src/lib/ai/service.ts");
  assert.match(service,/scope:"ai_generation"/);assert.match(service,/begin_ai_usage/);assert.match(service,/status:"succeeded"/);assert.match(service,/status:"failed"/);assert.match(service,/createAdminClient/);
});

test("AI prompts treat customer context as untrusted and prohibit invented critical facts",async()=>{
  const actions=await read("../src/features/ai/actions.ts");
  assert.match(actions,/DADO NÃO CONFIÁVEL/i);assert.match(actions,/Nunca invente preço, desconto, prazo, garantia/i);assert.match(actions,/não execute ações e não alegue que enviou mensagens/i);assert.match(actions,/Sugestão/i);
});

test("lead response is suggestion-only and does not expose contact fields to the model",async()=>{
  const actions=await read("../src/features/ai/actions.ts");const component=await read("../src/components/ai/lead-reply.tsx");
  assert.match(actions,/suggestLeadResponseAction/);assert.match(actions,/select\("name,source,status,tags,notes,interest,potential_value_cents,last_contact_at,next_contact_at"\)/);assert.doesNotMatch(actions,/select\("name,phone,whatsapp,email.*lead_response/);assert.match(component,/A mensagem não é enviada automaticamente/);assert.match(component,/Revise antes de enviar/);
});

test("Copilot receives bounded tenant context and never gets tools",async()=>{
  const actions=await read("../src/features/ai/actions.ts");const provider=await read("../src/lib/ai/openai.ts");
  assert.match(actions,/\.limit\(30\)/);assert.match(actions,/\.limit\(25\)/);assert.match(actions,/\.limit\(20\)/);assert.match(actions,/DADOS_NAO_CONFIAVEIS/);assert.doesNotMatch(provider,/tools\s*:/);
});

test("monthly AI reservation is serialized per tenant to resist concurrent limit races",async()=>{
  const sql=await read("../supabase/migrations/202608150014_ai_usage_provider.sql");
  assert.match(sql,/pg_advisory_xact_lock\(hashtext\(p_organization_id::text\)::bigint\)/i);
});
