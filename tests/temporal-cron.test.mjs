import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql = fs.readFileSync(new URL('../supabase/migrations/202608150035_temporal_automation_cron.sql', import.meta.url), 'utf8');

test('Supabase Cron agenda worker temporal diretamente no banco', () => {
  assert.match(sql, /create extension if not exists pg_cron/i);
  assert.match(sql, /cron\.schedule/);
  assert.match(sql, /platform-temporal-automations/);
  assert.match(sql, /\*\/5 \* \* \* \*/);
  assert.match(sql, /run_temporal_automations\(now\(\), 500\)/);
});
