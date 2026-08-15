import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const read=(p)=>readFile(new URL(p,import.meta.url),"utf8");

test("message template library is editable and does not auto-send",async()=>{
  const lib=await read("../src/lib/communications/templates.ts");const fields=await read("../src/components/communications/template-fields.tsx");
  assert.match(lib,/first_contact/);assert.match(lib,/quote_follow_up/);assert.match(lib,/availability/);
  assert.match(fields,/O modelo apenas preenche os campos\. Revise antes de enviar/);
  assert.match(fields,/só é enviado ao clicar no botão/);
  assert.doesNotMatch(fields,/fetch\(|sendTransactionalEmail|sendWhatsApp/);
});

test("central atendimento is tenant-scoped and distinguishes provider acceptance from delivery",async()=>{
  const page=await read("../src/app/atendimento/page.tsx");const nav=await read("../src/components/dashboard/nav.tsx");const proxy=await read("../src/lib/supabase/proxy.ts");
  assert.match(page,/communication_messages/);assert.match(page,/eq\("organization_id", organization\.id\)/);assert.match(page,/entrega\/leitura só aparecem quando confirmadas por Webhook/);
  assert.match(page,/Abrir lead/);assert.match(nav,/Atendimento/);assert.match(proxy,/\/atendimento/);
});
