import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const read=p=>readFile(new URL(p,import.meta.url),"utf8");

test("white-label domains only resolve publicly after provider verification",async()=>{const sql=await read("../supabase/migrations/202608150025_white_label_domains.sql");assert.match(sql,/create table public\.organization_branding/i);assert.match(sql,/create table public\.custom_domains/i);assert.match(sql,/d\.status='active' and d\.provider_verified=true/i);assert.match(sql,/service_organization_has_feature\(o\.id,'white_label'\)/i);assert.match(sql,/grant execute on function public\.resolve_public_custom_domain\(text\) to anon,authenticated/i);});

test("Vercel domain integration uses server-side REST API and never exposes access token",async()=>{const client=await read("../src/lib/white-label/vercel-domains.ts");const env=await read("../.env.example");assert.match(client,/api\.vercel\.com/);assert.match(client,/\/v10\/projects\/\$\{encodeURIComponent\(project\)\}\/domains/);assert.match(client,/\/v9\/projects\/\$\{encodeURIComponent\(project\)\}\/domains\/\$\{encodeURIComponent\(domain\)\}\/verify/);assert.match(env,/^VERCEL_ACCESS_TOKEN=$/m);assert.doesNotMatch(env,/NEXT_PUBLIC_VERCEL_ACCESS_TOKEN/);});

test("custom domain routing uses Next Proxy rewrite to the verified tenant slug",async()=>{const proxy=await read("../src/proxy.ts");const rewrite=await read("../src/lib/white-label/domain-rewrite.ts");assert.match(proxy,/customDomainRewrite/);assert.match(rewrite,/resolve_public_custom_domain/);assert.match(rewrite,/NextResponse\.rewrite/);assert.match(rewrite,/\/empresa\/\$\{encodeURIComponent\(slug\)\}/);});

test("branding is applied to public metadata and dashboard without publishing fake domain status",async()=>{const page=await read("../src/app/empresa/[slug]/page.tsx");const nav=await read("../src/components/dashboard/nav.tsx");const actions=await read("../src/features/white-label/actions.ts");assert.match(page,/get_public_branding/);assert.match(page,/favicon_url/);assert.match(nav,/organization_branding/);assert.match(actions,/safe\.verified\?"active":"verifying"/);assert.match(actions,/vercelDomainsConfigured/);});
