import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql = fs.readFileSync(new URL('../supabase/migrations/202608150033_security_advisor_hardening.sql', import.meta.url), 'utf8');

test('SECURITY DEFINER é fechado para anon por padrão e só RPCs públicas são reabertas', () => {
  assert.match(sql, /where n\.nspname = 'public'[\s\S]*p\.prosecdef/);
  assert.match(sql, /revoke execute on function %s from public, anon/);
  assert.match(sql, /grant execute on function public\.get_public_site\(text\) to anon, authenticated/);
  assert.match(sql, /grant execute on function public\.respond_public_quote\(text,text\) to anon, authenticated/);
  assert.match(sql, /grant execute on function public\.public_create_appointment/);
});

test('funções service-only não ficam executáveis por authenticated', () => {
  assert.match(sql, /p\.proname like 'service\\_%'/);
  assert.match(sql, /revoke execute on function %s from authenticated/);
  assert.match(sql, /revoke execute on function public\.apply_coupon_redemption\(uuid\) from authenticated/);
});

test('search_path mutável e extensão pública desnecessária são corrigidos', () => {
  assert.match(sql, /alter function public\.set_updated_at\(\) set search_path = public/);
  assert.match(sql, /alter function public\.safe_slug\(text\) set search_path = public/);
  assert.match(sql, /drop extension if exists btree_gist/);
});
