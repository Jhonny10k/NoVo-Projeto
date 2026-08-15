import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql = fs.readFileSync(new URL('../supabase/migrations/202608150034_performance_advisor_hardening.sql', import.meta.url), 'utf8');

test('policies sinalizadas usam select auth.uid para initplan', () => {
  assert.match(sql, /id = \(select auth\.uid\(\)\)/);
  assert.match(sql, /user_id = \(select auth\.uid\(\)\)/);
  assert.match(sql, /actor_user_id = \(select auth\.uid\(\)\)/);
});

test('FKs operacionais recebem índices sem remover índices de banco recém-criado', () => {
  assert.match(sql, /appointments_lead_idx/);
  assert.match(sql, /quotes_customer_idx/);
  assert.match(sql, /subscriptions_org_idx/);
  assert.match(sql, /webhook_deliveries_event_idx/);
  assert.doesNotMatch(sql, /drop index/i);
});
