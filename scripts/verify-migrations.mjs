import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const dir = path.join(root, 'supabase', 'migrations');
const files = (await readdir(dir)).filter((name) => name.endsWith('.sql')).sort();

assert.ok(files.length > 0, 'Nenhuma migration SQL encontrada.');

const seen = new Set();
let expected = 1;
const combined = [];

for (const file of files) {
  const match = file.match(/^\d{8}(\d{4})_[a-z0-9_]+\.sql$/i);
  assert.ok(match, `Nome de migration fora do padrão: ${file}`);
  const seq = Number(match[1]);
  assert.equal(seq, expected, `Sequência de migration inválida em ${file}: esperado ${String(expected).padStart(4,'0')}.`);
  assert.ok(!seen.has(seq), `Número de migration duplicado: ${seq}`);
  seen.add(seq);
  expected += 1;

  const sql = await readFile(path.join(dir, file), 'utf8');
  assert.ok(sql.trim().length > 0, `Migration vazia: ${file}`);
  assert.ok(!/\bdrop\s+table\b/i.test(sql), `DROP TABLE proibido em migration incremental: ${file}`);
  assert.ok(!/service_role[^\n]{0,80}(browser|client|next_public)/i.test(sql), `Possível exposição indevida de service role em ${file}`);
  combined.push(`\n-- ${file}\n${sql}`);
}

const all = combined.join('\n');
const dynamicTenantRlsTables = new Set();
for (const match of all.matchAll(/tenant_tables\s+text\[\]\s*:=\s*array\[(.*?)\];/gis)) {
  for (const item of match[1].matchAll(/'([a-z0-9_]+)'/gi)) dynamicTenantRlsTables.add(item[1]);
}
const tenantTables = [
  'organizations','organization_members','categories','products','services','pipelines','pipeline_stages',
  'leads','customers','quote_requests','quotes','quote_items','tasks','appointments','automations',
  'notifications','site_configs','site_sections','domains','events','organization_units','organization_member_units'
];
for (const table of tenantTables) {
  const create = new RegExp(`create\\s+table(?:\\s+if\\s+not\\s+exists)?\\s+public\\.${table}\\b`, 'i');
  if (!create.test(all)) continue;
  const rls = new RegExp(`alter\\s+table\\s+public\\.${table}\\s+enable\\s+row\\s+level\\s+security`, 'i');
  assert.ok(rls.test(all) || dynamicTenantRlsTables.has(table), `Tabela tenant ${table} foi criada sem ENABLE ROW LEVEL SECURITY.`);
}

assert.ok(/create\s+or\s+replace\s+function\s+public\.is_org_member\b/i.test(all), 'Helper is_org_member ausente.');
assert.ok(/create\s+or\s+replace\s+function\s+public\.has_org_role\b/i.test(all), 'Helper has_org_role ausente.');
assert.ok(/create\s+or\s+replace\s+function\s+public\.can_access_unit_scope\b/i.test(all), 'Helper can_access_unit_scope ausente.');
assert.ok(/security\s+definer/i.test(all), 'Nenhuma função SECURITY DEFINER encontrada; cadeia parece incompleta.');

console.log(`Migrations OK: ${files.length} arquivos, sequência 0001-${String(files.length).padStart(4,'0')}, sem DROP TABLE e com RLS nos núcleos tenant.`);
