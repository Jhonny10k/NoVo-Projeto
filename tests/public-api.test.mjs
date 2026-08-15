import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const read=p=>readFile(new URL(p,import.meta.url),"utf8");

test("public API keys are server-only, scoped and consume quota atomically",async()=>{const sql=await read("../supabase/migrations/202608150023_public_api.sql");assert.match(sql,/create table public\.api_keys/i);assert.match(sql,/secret_hash text not null unique/i);assert.doesNotMatch(sql,/create policy[^;]*api_keys/is);assert.match(sql,/for update/i);assert.match(sql,/api_usage_windows/i);assert.match(sql,/request_count < v_limit/i);assert.match(sql,/p_required_scope=any\(v_key\.scopes\)/i);assert.match(sql,/grant execute on function public\.service_consume_public_api_key\(text,text\) to service_role/i);});

test("API key material is random, peppered and never stored raw",async()=>{const keys=await read("../src/lib/public-api/keys.ts");const env=await read("../.env.example");assert.match(keys,/randomBytes\(32\)/);assert.match(keys,/createHmac\("sha256",pepper\(\)\)/);assert.match(keys,/PUBLIC_API_KEY_PEPPER/);assert.match(env,/^PUBLIC_API_KEY_PEPPER=$/m);assert.doesNotMatch(env,/NEXT_PUBLIC_PUBLIC_API_KEY_PEPPER/);});

test("public API routes bind every query to authenticated organization and explicit scope",async()=>{const auth=await read("../src/lib/public-api/auth.ts");const leads=await read("../src/app/api/v1/leads/route.ts");const customers=await read("../src/app/api/v1/customers/route.ts");const quotes=await read("../src/app/api/v1/quotes/route.ts");assert.match(auth,/service_consume_public_api_key/);assert.match(leads,/"leads:read"/);assert.match(leads,/"leads:write"/);assert.match(leads,/service_create_api_lead/);assert.match(customers,/"customers:read"/);assert.match(quotes,/"quotes:read"/);for(const source of [leads,customers,quotes])assert.match(source,/context\.organizationId/);});

test("admin config controls API and webhook quotas instead of hardcoding enterprise plan",async()=>{const ent=await read("../src/lib/plans/entitlements.ts");const admin=await read("../src/features/admin/actions.ts");const sql=await read("../supabase/migrations/202608150023_public_api.sql");assert.match(ent,/public_api/);assert.match(ent,/outbound_webhooks/);assert.match(ent,/white_label/);assert.match(admin,/admin_update_plan_limits/);assert.match(sql,/api_requests_per_hour/);});
