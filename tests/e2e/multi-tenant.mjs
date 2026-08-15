import assert from "node:assert/strict";

const required = [
  "E2E_SUPABASE_URL",
  "E2E_SUPABASE_PUBLISHABLE_KEY",
  "E2E_USER_A_EMAIL",
  "E2E_USER_A_PASSWORD",
  "E2E_USER_B_EMAIL",
  "E2E_USER_B_PASSWORD"
];
for (const key of required) {
  if (!process.env[key]) throw new Error(`${key} é obrigatório para o teste E2E.`);
}

const base = process.env.E2E_SUPABASE_URL.replace(/\/$/, "");
const apiKey = process.env.E2E_SUPABASE_PUBLISHABLE_KEY;

async function signIn(email, password) {
  const response = await fetch(`${base}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password })
  });
  assert.equal(response.ok, true, `Falha no login E2E de ${email}: ${await response.text()}`);
  const body = await response.json();
  assert.ok(body.access_token);
  return body.access_token;
}

async function rest(token, path) {
  const response = await fetch(`${base}/rest/v1/${path}`, {
    headers: { apikey: apiKey, Authorization: `Bearer ${token}`, Accept: "application/json" }
  });
  assert.equal(response.ok, true, `PostgREST falhou: ${response.status} ${await response.text()}`);
  return response.json();
}

const [tokenA, tokenB] = await Promise.all([
  signIn(process.env.E2E_USER_A_EMAIL, process.env.E2E_USER_A_PASSWORD),
  signIn(process.env.E2E_USER_B_EMAIL, process.env.E2E_USER_B_PASSWORD)
]);

const [orgsA, orgsB] = await Promise.all([
  rest(tokenA, "organizations?select=id,name&order=created_at.asc&limit=1"),
  rest(tokenB, "organizations?select=id,name&order=created_at.asc&limit=1")
]);
assert.equal(orgsA.length, 1, "Usuário A precisa enxergar uma organização de teste.");
assert.equal(orgsB.length, 1, "Usuário B precisa enxergar uma organização de teste.");
assert.notEqual(orgsA[0].id, orgsB[0].id, "As contas E2E precisam pertencer a tenants diferentes.");

const [aReadsB, bReadsA, aLeadsFromB, bLeadsFromA] = await Promise.all([
  rest(tokenA, `organizations?select=id&id=eq.${encodeURIComponent(orgsB[0].id)}`),
  rest(tokenB, `organizations?select=id&id=eq.${encodeURIComponent(orgsA[0].id)}`),
  rest(tokenA, `leads?select=id,organization_id&organization_id=eq.${encodeURIComponent(orgsB[0].id)}&limit=1`),
  rest(tokenB, `leads?select=id,organization_id&organization_id=eq.${encodeURIComponent(orgsA[0].id)}&limit=1`)
]);

assert.deepEqual(aReadsB, [], "RLS falhou: usuário A enxergou a organização B.");
assert.deepEqual(bReadsA, [], "RLS falhou: usuário B enxergou a organização A.");
assert.deepEqual(aLeadsFromB, [], "RLS falhou: usuário A enxergou leads da organização B.");
assert.deepEqual(bLeadsFromA, [], "RLS falhou: usuário B enxergou leads da organização A.");

console.log(`E2E multi-tenant OK: ${orgsA[0].name} isolada de ${orgsB[0].name}.`);
