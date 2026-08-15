import { spawnSync } from 'node:child_process';
import { existsSync, writeFileSync } from 'node:fs';

const steps = [];
function run(name, command, args) {
  const started = Date.now();
  const result = spawnSync(command, args, { cwd: process.cwd(), stdio: 'inherit', shell: false, env: process.env });
  const item = { name, status: result.status === 0 ? 'pass' : 'fail', exitCode: result.status, durationMs: Date.now() - started };
  steps.push(item);
  return item.status === 'pass';
}
function blocked(name, reason) {
  steps.push({ name, status: 'blocked', reason });
  console.warn(`${name}: BLOCKED — ${reason}`);
}
function hasAll(keys) { return keys.every((key) => Boolean(process.env[key])); }

const migrationsOk = run('verify:migrations', process.execPath, ['scripts/verify-migrations.mjs']);
const testsOk = run('test', 'npm', ['run', 'test']);

const tenantKeys = ['E2E_SUPABASE_URL','E2E_SUPABASE_PUBLISHABLE_KEY','E2E_USER_A_EMAIL','E2E_USER_A_PASSWORD','E2E_USER_B_EMAIL','E2E_USER_B_PASSWORD'];
if (hasAll(tenantKeys)) run('e2e:tenant', 'npm', ['run', 'test:e2e:tenant']);
else blocked('e2e:tenant', 'credenciais E2E de dois tenants não configuradas');

const unitKeys = ['E2E_SUPABASE_URL','E2E_SUPABASE_PUBLISHABLE_KEY','E2E_UNIT_ADMIN_EMAIL','E2E_UNIT_ADMIN_PASSWORD','E2E_UNIT_MEMBER_EMAIL','E2E_UNIT_MEMBER_PASSWORD','E2E_UNIT_ALLOWED_ID','E2E_UNIT_BLOCKED_ID'];
if (hasAll(unitKeys)) run('e2e:units', 'npm', ['run', 'test:e2e:units']);
else blocked('e2e:units', 'credenciais/IDs E2E multiunidade não configurados');

if (existsSync('node_modules')) {
  run('lint', 'npm', ['run', 'lint']);
  run('typecheck', 'npm', ['run', 'typecheck']);
  run('build', 'npm', ['run', 'build']);
} else {
  blocked('lint', 'node_modules ausente');
  blocked('typecheck', 'node_modules ausente');
  blocked('build', 'node_modules ausente');
}

const externalConfig = {
  supabase: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SECRET_KEY),
  mercadoPago: Boolean(process.env.MERCADO_PAGO_ACCESS_TOKEN && process.env.MERCADO_PAGO_WEBHOOK_SECRET),
  resend: Boolean(process.env.RESEND_API_KEY && process.env.RESEND_WEBHOOK_SECRET),
  metaWhatsApp: Boolean(process.env.META_GRAPH_API_VERSION && process.env.META_WHATSAPP_APP_SECRET && process.env.META_WHATSAPP_VERIFY_TOKEN),
  googleCalendar: Boolean(process.env.GOOGLE_OAUTH_CLIENT_ID && process.env.GOOGLE_OAUTH_CLIENT_SECRET),
  googleMaps: Boolean(process.env.GOOGLE_MAPS_API_KEY),
  openai: Boolean(process.env.OPENAI_API_KEY),
  vercel: Boolean(process.env.VERCEL_ACCESS_TOKEN && (process.env.VERCEL_PROJECT_ID || process.env.VERCEL_PROJECT_NAME))
};

const failed = steps.some((step) => step.status === 'fail');
const blockedCount = steps.filter((step) => step.status === 'blocked').length;
const report = {
  generatedAt: new Date().toISOString(),
  overall: failed ? 'fail' : blockedCount ? 'partial' : 'pass',
  steps,
  externalConfig
};
writeFileSync('HOMOLOGATION_LOCAL.json', `${JSON.stringify(report, null, 2)}\n`);
console.log(`Relatório: HOMOLOGATION_LOCAL.json (${report.overall})`);
if (failed || !migrationsOk || !testsOk) process.exitCode = 1;
