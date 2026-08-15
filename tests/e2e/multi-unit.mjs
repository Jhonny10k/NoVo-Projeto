import assert from 'node:assert/strict';

const required = [
  'E2E_SUPABASE_URL',
  'E2E_SUPABASE_PUBLISHABLE_KEY',
  'E2E_UNIT_ADMIN_EMAIL',
  'E2E_UNIT_ADMIN_PASSWORD',
  'E2E_UNIT_MEMBER_EMAIL',
  'E2E_UNIT_MEMBER_PASSWORD',
  'E2E_UNIT_ALLOWED_ID',
  'E2E_UNIT_BLOCKED_ID'
];
for (const key of required) {
  if (!process.env[key]) throw new Error(`${key} é obrigatório para o teste E2E multiunidade.`);
}

const base = process.env.E2E_SUPABASE_URL.replace(/\/$/, '');
const apiKey = process.env.E2E_SUPABASE_PUBLISHABLE_KEY;

async function signIn(email, password) {
  const response = await fetch(`${base}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: apiKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password })
  });
  assert.equal(response.ok, true, `Falha no login E2E de ${email}: ${await response.text()}`);
  return (await response.json()).access_token;
}

async function rest(token, path) {
  const response = await fetch(`${base}/rest/v1/${path}`, {
    headers: { apikey: apiKey, Authorization: `Bearer ${token}`, Accept: 'application/json' }
  });
  assert.equal(response.ok, true, `PostgREST falhou: ${response.status} ${await response.text()}`);
  return response.json();
}

const [adminToken, memberToken] = await Promise.all([
  signIn(process.env.E2E_UNIT_ADMIN_EMAIL, process.env.E2E_UNIT_ADMIN_PASSWORD),
  signIn(process.env.E2E_UNIT_MEMBER_EMAIL, process.env.E2E_UNIT_MEMBER_PASSWORD)
]);

const allowed = encodeURIComponent(process.env.E2E_UNIT_ALLOWED_ID);
const blocked = encodeURIComponent(process.env.E2E_UNIT_BLOCKED_ID);

const [adminAllowed, adminBlocked, memberAllowed, memberBlocked, memberBlockedLeads] = await Promise.all([
  rest(adminToken, `organization_units?select=id,name&id=eq.${allowed}`),
  rest(adminToken, `organization_units?select=id,name&id=eq.${blocked}`),
  rest(memberToken, `organization_units?select=id,name&id=eq.${allowed}`),
  rest(memberToken, `organization_units?select=id,name&id=eq.${blocked}`),
  rest(memberToken, `leads?select=id,unit_id&unit_id=eq.${blocked}&limit=1`)
]);

assert.equal(adminAllowed.length, 1, 'Admin precisa enxergar a unidade permitida.');
assert.equal(adminBlocked.length, 1, 'Admin precisa enxergar todas as unidades da organização.');
assert.equal(memberAllowed.length, 1, 'Membro precisa enxergar a unidade explicitamente atribuída.');
assert.deepEqual(memberBlocked, [], 'RLS falhou: membro enxergou unidade não atribuída.');
assert.deepEqual(memberBlockedLeads, [], 'RLS falhou: membro enxergou lead de unidade não atribuída.');

console.log('E2E multiunidade OK: admin vê ambas as unidades; membro não acessa a unidade bloqueada nem seus leads.');
