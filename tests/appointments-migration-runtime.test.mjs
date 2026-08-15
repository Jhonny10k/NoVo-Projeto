import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const sql = readFileSync(new URL('../supabase/migrations/202608150011_appointments.sql', import.meta.url), 'utf8');
test('internal appointment conflict check declares and loads its buffer', () => {
  const fn = sql.match(/create or replace function public\.create_appointment[\s\S]*?revoke all on function public\.create_appointment/)?.[0] ?? '';
  assert.match(fn, /v_buffer integer := 0/);
  assert.match(fn, /select coalesce\(buffer_minutes,0\) into v_buffer/);
  assert.doesNotMatch(fn, /v_settings\.buffer_minutes/);
});
