import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const read=(path)=>readFile(new URL(path,import.meta.url),"utf8");

test("analytics stores pseudonymized visits without raw IP or user-agent columns",async()=>{
  const sql=await read("../supabase/migrations/202608150013_analytics_utm.sql");
  const route=await read("../src/app/api/track/visit/route.ts");
  assert.match(sql,/create table public\.site_visits/i);
  assert.match(sql,/visitor_hash text not null/i);
  assert.doesNotMatch(sql,/\bip_address\b|\buser_agent\b/i);
  assert.match(route,/requestFingerprint\(`/);
  assert.match(route,/consumeRateLimit/);
});

test("visit recording is server-only, tenant-aware and cannot block public UX",async()=>{
  const sql=await read("../supabase/migrations/202608150013_analytics_utm.sql");
  const tracker=await read("../src/components/analytics/visit-tracker.tsx");
  assert.match(sql,/grant execute on function public\.record_site_visit[\s\S]*to service_role/i);
  assert.match(sql,/revoke all on function public\.record_site_visit[\s\S]*from anon/i);
  assert.match(sql,/organization_has_entitlement\(o\.id,'analytics'\)/i);
  assert.match(sql,/created_at>now\(\)-interval '30 minutes'/i);
  assert.match(tracker,/Analytics nunca deve bloquear a experiência pública/);
});

test("UTM is preserved from public page into the created or existing lead",async()=>{
  const sql=await read("../supabase/migrations/202608150013_analytics_utm.sql");
  const renderer=await read("../src/components/site/site-renderer.tsx");
  const action=await read("../src/features/public-site/actions.ts");
  assert.match(sql,/add column if not exists utm_source/i);
  assert.match(sql,/update public\.leads set[\s\S]*utm_source=/i);
  assert.match(renderer,/name="utm_source"/);
  assert.match(action,/p_utm_source:/);
});

test("analytics summary uses real tenant data for funnel, revenue, sources and daily series",async()=>{
  const sql=await read("../supabase/migrations/202608150013_analytics_utm.sql");
  const page=await read("../src/app/analytics/page.tsx");
  assert.match(sql,/organization_analytics_summary/i);
  assert.match(sql,/count\(distinct visitor_hash\)/i);
  assert.match(sql,/status='approved'/i);
  assert.match(sql,/average_ticket_cents/i);
  assert.match(sql,/lead_sources/i);
  assert.match(sql,/utm_mediums/i);
  assert.match(sql,/top_items/i);
  assert.match(sql,/generate_series/i);
  assert.match(page,/Resultados do negócio/);
  assert.match(page,/Sem promessa de resultado/);
});

test("visitor conversion uses site-originated leads and reports allow a bounded custom period",async()=>{
  const sql=await read("../supabase/migrations/202608150013_analytics_utm.sql");
  const page=await read("../src/app/analytics/page.tsx");
  assert.match(sql,/'site_leads'.*source='site'/is);
  assert.match(page,/pct\(s\.site_leads\?\?0,s\.visitors\?\?0\)/);
  assert.match(page,/raw>=7&&raw<=365/);
  assert.match(page,/Período personalizado/);
});
