import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const read=p=>readFile(new URL(p,import.meta.url),"utf8");

test("webhook SSRF guard blocks precise reserved IPv4 ranges without overblocking whole public /16 networks",async()=>{
  const src=await read("../src/lib/public-api/webhook-security.ts");
  assert.match(src,/a===198&&b===51&&c===100/);
  assert.match(src,/a===203&&b===0&&c===113/);
  assert.doesNotMatch(src,/\(a===198&&b===51\)\|\|\(a===203&&b===0\)/);
});

test("IPv4-mapped IPv6 webhook targets are normalized through the IPv4 private-range check",async()=>{
  const src=await read("../src/lib/public-api/webhook-security.ts");
  assert.match(src,/v\.startsWith\("::ffff:"\)/);
  assert.match(src,/return privateV4\(mapped\)/);
});
