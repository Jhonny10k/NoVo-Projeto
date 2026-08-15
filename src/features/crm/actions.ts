"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/require-user";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { parseMoneyToCents } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import { requireFeature } from "@/lib/plans/entitlements";

function field(formData: FormData, key: string, max = 3000) {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

async function context() {
  await requireFeature("crm");
  const [organization, user, supabase] = await Promise.all([
    requireCurrentOrganization(),
    requireUser(),
    createClient()
  ]);
  return { organization, user, supabase };
}

export async function createLeadAction(formData: FormData) {
  const { organization, user, supabase } = await context();
  const name = field(formData, "name", 160);
  const whatsapp = field(formData, "whatsapp", 80);
  const email = field(formData, "email", 254).toLowerCase();
  const interest = field(formData, "interest", 1000);
  const unitId = field(formData, "unit_id", 80) || null;
  const potentialValue = parseMoneyToCents(field(formData, "potential_value", 40));
  if (name.length < 2 || (!whatsapp && !email)) redirect("/crm?erro=campos");

  const { data: pipeline } = await supabase
    .from("pipelines")
    .select("id")
    .eq("organization_id", organization.id)
    .eq("is_default", true)
    .limit(1)
    .maybeSingle();
  const pipelineId = pipeline?.id ?? null;
  const { data: stage } = pipelineId ? await supabase.from("pipeline_stages").select("id").eq("pipeline_id", pipelineId).eq("stage_key", "new").maybeSingle() : { data: null };

  const { data: createdLead, error } = await supabase.from("leads").insert({
    organization_id: organization.id,
    unit_id: unitId,
    pipeline_id: pipelineId,
    stage_id: stage?.id ?? null,
    name,
    whatsapp: whatsapp || null,
    email: email || null,
    interest: interest || null,
    potential_value_cents: potentialValue,
    source: "manual",
    status: "new",
    created_by: user.id
  }).select("id").single();
  if (error || !createdLead) redirect("/crm?erro=salvar");
  await supabase.from("events").insert({ organization_id: organization.id, actor_user_id: user.id, entity_type: "lead", entity_id: createdLead.id, event_type: "lead_created", metadata: { source: "manual" } });
  revalidatePath("/crm");
  redirect("/crm?status=lead-criado");
}

export async function moveLeadStageAction(formData: FormData) {
  const { organization, user, supabase } = await context();
  const leadId = field(formData, "lead_id", 80);
  const stageId = field(formData, "stage_id", 80);
  if (!leadId || !stageId) redirect("/crm?erro=campos");
  const { data: stage } = await supabase.from("pipeline_stages").select("id,stage_key").eq("organization_id", organization.id).eq("id", stageId).maybeSingle();
  if (!stage) redirect("/crm?erro=stage");

  const { error } = await supabase.from("leads").update({ stage_id: stage.id, status: stage.stage_key, last_contact_at: new Date().toISOString() }).eq("organization_id", organization.id).eq("id", leadId);
  if (error) redirect("/crm?erro=salvar");
  await supabase.from("events").insert({ organization_id: organization.id, actor_user_id: user.id, entity_type: "lead", entity_id: leadId, event_type: "lead_stage_changed", metadata: { stage_id: stage.id, stage_key: stage.stage_key } });
  revalidatePath("/crm");
}

export async function convertLeadToCustomerAction(formData: FormData) {
  const { organization, supabase } = await context();
  const leadId = field(formData, "lead_id", 80);
  if (!leadId) redirect("/crm?erro=campos");
  const { error } = await supabase.rpc("convert_lead_to_customer", { p_organization_id: organization.id, p_lead_id: leadId });
  if (error) redirect("/crm?erro=converter");
  revalidatePath("/crm");
  revalidatePath("/clientes");
  redirect("/clientes?status=convertido");
}

export async function updatePipelineStageAction(formData: FormData) {
  const { organization, supabase } = await context();
  if (!["owner","admin"].includes(organization.role)) redirect("/crm?erro=permissao");
  const stageId = field(formData,"stage_id",80);
  const name = field(formData,"name",100);
  const rawOrder = Number(field(formData,"sort_order",10));
  const sortOrder = Number.isInteger(rawOrder) ? Math.max(0,Math.min(10000,rawOrder)) : 0;
  if (!stageId || name.length < 2) redirect("/crm?erro=etapa");
  const { error } = await supabase.from("pipeline_stages").update({ name, sort_order:sortOrder }).eq("organization_id",organization.id).eq("id",stageId);
  if (error) redirect("/crm?erro=etapa");
  revalidatePath("/crm");
  redirect("/crm?status=etapa-salva");
}

export async function scheduleLeadFollowUpAction(formData: FormData) {
  const { organization, supabase } = await context();
  const leadId = field(formData,"lead_id",80);
  const localDatetime = field(formData,"next_contact_at",40);
  if (!leadId || !localDatetime) redirect(`/crm/${leadId || ""}?erro=followup`);
  const { error } = await supabase.rpc("schedule_lead_followup", { p_organization_id:organization.id, p_lead_id:leadId, p_local_datetime:localDatetime });
  if (error) redirect(`/crm/${leadId}?erro=followup`);
  revalidatePath(`/crm/${leadId}`);
  revalidatePath("/dashboard");
  redirect(`/crm/${leadId}?status=followup`);
}
