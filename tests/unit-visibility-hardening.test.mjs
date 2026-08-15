import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync('supabase/migrations/202608150036_unit_visibility_hardening.sql', 'utf8');
const e2e = readFileSync('tests/e2e/multi-unit.mjs', 'utf8');

test('organization unit SELECT is restricted by explicit unit scope', () => {
  assert.match(sql, /drop policy if exists organization_units_select_member/i);
  assert.match(sql, /create policy organization_units_select_member[\s\S]*can_access_unit_scope\(organization_id, id\)/i);
});

test('enterprise unit RPC uses the same unit-aware visibility rule', () => {
  assert.match(sql, /create or replace function public\.list_enterprise_units/i);
  assert.match(sql, /can_access_unit_scope\(p_organization_id, u\.id\)/i);
});

test('real E2E contract requires blocked units and their leads to stay invisible', () => {
  assert.match(e2e, /memberBlocked[\s\S]*deepEqual\(memberBlocked, \[\]/i);
  assert.match(e2e, /memberBlockedLeads[\s\S]*deepEqual\(memberBlockedLeads, \[\]/i);
});
