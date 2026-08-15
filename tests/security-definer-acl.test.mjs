import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sql = await readFile('supabase/migrations/202608150031_security_definer_acl_hardening.sql','utf8');

const internalFunctions = [
  'handle_new_user()',
  'activate_invited_memberships()',
  'initialize_organization_trial()',
  'initialize_site_sections()',
  'enforce_quote_request_entitlement()',
  'organization_has_entitlement(uuid,text)',
  'user_can_access_unit(uuid,uuid,uuid)',
  'sync_commercial_unit()',
  'sync_event_unit()'
];

test('internal SECURITY DEFINER functions are not executable by PUBLIC/anon/authenticated', () => {
  for (const signature of internalFunctions) {
    const escaped = signature.replace(/[()]/g, '\\$&');
    assert.match(sql, new RegExp(`revoke all on function public\\.${escaped} from public, anon, authenticated;`, 'i'));
  }
});

test('hardening migration does not revoke intentional public business RPCs', () => {
  for (const name of ['get_public_site', 'public_create_quote_request', 'get_public_quote', 'respond_public_quote', 'get_public_booking', 'public_create_appointment']) {
    assert.doesNotMatch(sql, new RegExp(`revoke all on function public\\.${name}`, 'i'));
  }
});
