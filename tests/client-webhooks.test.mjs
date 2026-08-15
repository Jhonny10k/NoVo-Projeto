import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const read=p=>readFile(new URL(p,import.meta.url),"utf8");

test("client webhooks reuse transactional outbox with delivery idempotency",async()=>{const sql=await read("../supabase/migrations/202608150024_client_webhooks.sql");assert.match(sql,/client_webhook/);assert.match(sql,/unique\(endpoint_id,event_id\)/i);assert.match(sql,/on conflict\(dedupe_key\) do nothing/i);assert.match(sql,/events_enqueue_client_webhooks/i);assert.doesNotMatch(sql,/http_post|net\.http|fetch\(/i);});

test("webhook signing secrets remain encrypted and unavailable to tenant PostgREST",async()=>{const sql=await read("../supabase/migrations/202608150024_client_webhooks.sql");const actions=await read("../src/features/developer/actions.ts");assert.match(sql,/create table public\.webhook_endpoint_secrets/i);assert.doesNotMatch(sql,/create policy[^;]*webhook_endpoint_secrets/is);assert.match(actions,/encryptIntegrationSecret\(secret\)/);assert.match(actions,/whsec_/);});

test("outbound webhook delivery signs raw body, has timeout, no redirects and retry/dead-letter",async()=>{const sender=await read("../src/lib/public-api/client-webhook.ts");const worker=await read("../src/lib/outbox/worker.ts");assert.match(sender,/createHmac\("sha256",signingSecret\)/);assert.match(sender,/`\$\{timestamp\}\.\$\{body\}`/);assert.match(sender,/x-nd-signature/);assert.match(sender,/idempotency-key/);assert.match(sender,/redirect:"error"/);assert.match(sender,/setTimeout\(\(\)=>controller\.abort\(\),10000\)/);assert.match(worker,/deliverClientWebhook/);assert.match(worker,/webhook_deliveries/);assert.match(worker,/failureStatus==="dead_letter"/);});

test("webhook URL validation blocks local/private destinations before delivery",async()=>{const security=await read("../src/lib/public-api/webhook-security.ts");assert.match(security,/url\.protocol!=="https:"/);assert.match(security,/localhost/);assert.match(security,/\.internal/);assert.match(security,/lookup\(host,\{all:true/);assert.match(security,/isPrivateOrReservedAddress/);});
