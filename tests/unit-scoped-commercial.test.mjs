import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql=readFileSync('supabase/migrations/202608150027_unit_scoped_commercial.sql','utf8');
const crm=readFileSync('src/features/crm/actions.ts','utf8');
const tasks=readFileSync('src/features/tasks/actions.ts','utf8');
const crmPage=readFileSync('src/app/crm/page.tsx','utf8');
const taskPage=readFileSync('src/app/tarefas/page.tsx','utf8');

test('commercial records gain nullable unit scope without arbitrary legacy assignment',()=>{
  for(const table of ['leads','customers','quote_requests','quotes','quote_items','tasks','appointments','events']) assert.match(sql,new RegExp(`alter table public\\.${table} add column if not exists unit_id uuid`));
  assert.match(sql,/unit_id NULL significa escopo geral/i);
  assert.doesNotMatch(sql,/update public\.leads[\s\S]{0,300}set unit_id\s*=\s*\(select/i);
});

test('RLS and security-definer commercial flows enforce accessible unit scope',()=>{
  assert.match(sql,/can_access_unit_scope/);
  assert.match(sql,/t\|\|'_select_member'[\s\S]*can_access_unit_scope/i);
  assert.match(sql,/create or replace function public\.convert_lead_to_customer[\s\S]*can_access_unit_scope/i);
  assert.match(sql,/create or replace function public\.create_quote_with_items[\s\S]*can_access_unit_scope/i);
  assert.match(sql,/create or replace function public\.create_appointment[\s\S]*can_access_unit_scope/i);
});

test('events, notifications, dashboard and calendar are unit aware too',()=>{
  assert.match(sql,/events_sync_unit/);
  assert.match(sql,/user_can_access_unit\(new\.organization_id,m\.user_id,new\.unit_id\)/);
  assert.match(sql,/organization_dashboard_summary[\s\S]*can_access_unit_scope/i);
  assert.match(sql,/appointments_calendar[\s\S]*can_access_unit_scope/i);
});

test('organization-wide analytics is restricted for non-admins in multi-unit mode',()=>{
  assert.match(sql,/organization_analytics_summary_orgwide/);
  assert.match(sql,/multi_unit[\s\S]*owner','admin[\s\S]*analytics requires organization admin in multi-unit mode/i);
});

test('CRM and tasks let authorized users assign accessible units without trusting arbitrary labels',()=>{
  assert.match(crm,/unit_id: unitId/);
  assert.match(tasks,/unit_id: unitId/);
  assert.match(crmPage,/list_accessible_units/);
  assert.match(taskPage,/list_accessible_units/);
});
