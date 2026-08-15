import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const read=(path)=>readFile(new URL(path,import.meta.url),"utf8");

test("orçamento possui visual profissional imprimível e saída PDF nativa sem fingir arquivo server-side", async()=>{
  const page=await read("../src/app/orcamentos/[id]/imprimir/page.tsx");
  const css=await read("../src/app/globals.css");
  assert.match(page,/Imprimir \/ Salvar PDF/);
  assert.match(page,/logo_url/);
  assert.match(page,/Cliente/);
  assert.match(css,/@media print/);
  assert.match(css,/@page \{ size: A4/);
});

test("perfil próprio usa RLS existente e preferências estruturadas", async()=>{
  const sql=await read("../supabase/migrations/202608150010_profile_company_coupons.sql");
  const action=await read("../src/features/profile/actions.ts");
  assert.match(sql,/notification_preferences jsonb/i);
  assert.match(action,/\.from\("profiles"\)\.update/);
  assert.match(action,/notify_appointments/);
  assert.match(action,/folder: "profile"/);
});

test("configurações da empresa exigem owner ou admin e alimentam identidade comercial", async()=>{
  const action=await read("../src/features/settings/actions.ts");
  const page=await read("../src/app/configuracoes/page.tsx");
  assert.match(action,/\["owner", "admin"\]/);
  assert.match(action,/logo_url/);
  assert.match(action,/business_hours/);
  assert.match(page,/Dados da empresa/);
});

test("cupons são globais, administrados por RPC e validados no checkout", async()=>{
  const sql=await read("../supabase/migrations/202608150010_profile_company_coupons.sql");
  const billing=await read("../src/features/billing/actions.ts");
  assert.match(sql,/create table public\.coupons/i);
  assert.match(sql,/admin_save_coupon/i);
  assert.match(sql,/validate_coupon_for_checkout/i);
  assert.match(billing,/validate_coupon_for_checkout/);
  assert.match(billing,/list_amount_cents/);
  assert.match(billing,/coupon_id/);
});

test("cupom só é consumido quando checkout foi autorizado e resgate é idempotente", async()=>{
  const sql=await read("../supabase/migrations/202608150010_profile_company_coupons.sql");
  const sync=await read("../src/lib/billing/sync.ts");
  assert.match(sql,/status <> 'authorized'/i);
  assert.match(sql,/on conflict \(checkout_session_id\) do nothing/i);
  assert.match(sql,/grant execute on function public\.apply_coupon_redemption\(uuid\) to service_role/i);
  assert.match(sync,/checkoutStatus === "authorized"/);
  assert.match(sync,/apply_coupon_redemption/);
});

test("agenda interna é protegida por entitlement, papel e conflito do profissional", async()=>{
  const sql=await read("../supabase/migrations/202608150011_appointments.sql");
  const action=await read("../src/features/appointments/actions.ts");
  assert.match(sql,/create table public\.appointments/i);
  assert.match(sql,/public\.has_feature\(p_organization_id,'appointments'\)/i);
  assert.match(sql,/schedule conflict/i);
  assert.match(action,/requireFeature\("appointments"\)/);
  assert.match(action,/rpc\("create_appointment"/);
});

test("agendamento público valida entitlement, disponibilidade e colisão antes de criar", async()=>{
  const sql=await read("../supabase/migrations/202608150011_appointments.sql");
  const action=await read("../src/features/appointments/actions.ts");
  assert.match(sql,/organization_has_entitlement\(v_org.id,'appointments'\)/i);
  assert.match(sql,/outside availability/i);
  assert.match(sql,/tstzrange\(a\.starts_at-make_interval\(mins=>v_settings\.buffer_minutes\),a\.ends_at\+make_interval\(mins=>v_settings\.buffer_minutes\),'\[\)'\) && tstzrange\(v_start,v_end,'\[\)'\)/i);
  assert.match(sql,/'booking','new',v_service\.name/i);
  assert.match(action,/scope:"public_booking"/);
  assert.match(action,/public_create_appointment/);
});

test("agenda gera notificações reais a partir dos eventos do domínio", async()=>{
  const sql=await read("../supabase/migrations/202608150011_appointments.sql");
  assert.match(sql,/when 'appointment_created'/i);
  assert.match(sql,/when 'appointment_status_changed'/i);
  assert.match(sql,/insert into public\.notifications/i);
  assert.match(sql,/notification_preferences->>v_pref_key/i);
});
