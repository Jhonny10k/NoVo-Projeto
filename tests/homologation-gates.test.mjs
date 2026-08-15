import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const pkg = JSON.parse(await readFile('package.json','utf8'));
const runner = await readFile('scripts/homologation-local.mjs','utf8');
const verifier = await readFile('scripts/verify-migrations.mjs','utf8');
const envExample = await readFile('.env.example','utf8');

test('homologation runner never marks missing dependencies as pass', () => {
  assert.match(runner, /blocked\('lint', 'node_modules ausente'\)/);
  assert.match(runner, /blocked\('typecheck', 'node_modules ausente'\)/);
  assert.match(runner, /blocked\('build', 'node_modules ausente'\)/);
});

test('homologation runner conditionally executes tenant and multi-unit E2E', () => {
  assert.match(runner, /test:e2e:tenant/);
  assert.match(runner, /test:e2e:units/);
  assert.match(envExample, /E2E_UNIT_ALLOWED_ID=/);
  assert.match(envExample, /E2E_UNIT_BLOCKED_ID=/);
});

test('migration verifier enforces contiguous sequence and forbids DROP TABLE', () => {
  assert.match(verifier, /Sequência de migration inválida/);
  assert.match(verifier, /DROP TABLE proibido/);
  assert.match(verifier, /dynamicTenantRlsTables/);
});

test('package scripts expose reproducible homologation gates', () => {
  assert.equal(pkg.scripts['verify:migrations'], 'node scripts/verify-migrations.mjs');
  assert.equal(pkg.scripts['homologate:local'], 'node scripts/homologation-local.mjs');
  assert.equal(pkg.scripts['test:e2e:tenant'], 'node tests/e2e/multi-tenant.mjs');
  assert.equal(pkg.scripts['test:e2e:units'], 'node tests/e2e/multi-unit.mjs');
});
