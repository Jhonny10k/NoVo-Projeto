import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../supabase/migrations/202608150032_data_api_explicit_grants.sql', import.meta.url), 'utf8').toLowerCase();

test('Data API grants are explicit for new Supabase projects', () => {
  assert.match(sql, /revoke all privileges on all tables in schema public from anon/);
  assert.match(sql, /grant select on table public\.plans to anon/);
  assert.match(sql, /grant select, insert, update, delete on all tables in schema public to authenticated/);
  assert.match(sql, /grant all privileges on all tables in schema public to service_role/);
});

test('anonymous Data API access is not broadly granted', () => {
  assert.doesNotMatch(sql, /grant\s+(?:all|select,?\s*insert|select, insert, update, delete)\s+on all tables in schema public to anon/);
});
