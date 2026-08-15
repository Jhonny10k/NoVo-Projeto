import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync('supabase/migrations/202608150026_enterprise_units.sql','utf8');
const actions = readFileSync('src/features/units/actions.ts','utf8');
const page = readFileSync('src/app/unidades/page.tsx','utf8');
const adminActions = readFileSync('src/features/admin/actions.ts','utf8');
const adminPage = readFileSync('src/app/admin/page.tsx','utf8');

test('multi-unit is an entitlement with configurable unit quota', () => {
  assert.match(migration, /"multi_unit":false/);
  assert.match(migration, /"units":5/);
  assert.match(adminActions, /limit_units/);
  assert.match(adminPage, /name="limit_units"/);
});

test('unit membership remains tenant scoped and does not silently repartition commercial data', () => {
  assert.match(migration, /organization_member_units/);
  assert.match(migration, /member_can_access_unit/);
  assert.match(migration, /NÃO altera silenciosamente/i);
  assert.doesNotMatch(migration, /alter table public\.(leads|quotes|customers)[\s\S]*add column[\s\S]*unit_id/i);
});

test('unit management requires plan feature and privileged role', () => {
  assert.match(actions, /requireFeature\("multi_unit"\)/);
  assert.match(actions, /\["owner","admin"\]/);
  assert.match(actions, /getFeatureLimit\("units"\)/);
});

test('unit member assignments are explicit and UI explains the current scope boundary', () => {
  assert.match(actions, /organization_member_units/);
  assert.match(page, /escopo geral|registros comerciais|unidade/i);
});
