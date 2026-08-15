import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const read=p=>readFile(new URL(p,import.meta.url),"utf8");

test("Zapier Make and n8n recipes reuse generic API and signed webhooks",async()=>{
  const page=await read("../src/app/desenvolvedores/receitas/page.tsx");
  const docs=await read("../docs/AUTOMATION_RECIPES.md");
  for(const content of [page,docs]){
    assert.match(content,/Zapier/);
    assert.match(content,/Make/);
    assert.match(content,/n8n/);
    assert.match(content,/HMAC/i);
    assert.match(content,/idempot/i);
  }
  assert.match(docs,/\/api\/v1\/openapi\.json/);
  assert.match(docs,/leads:write/);
  assert.doesNotMatch(docs,/ZAPIER_API_KEY|MAKE_API_KEY|N8N_API_KEY/);
});
