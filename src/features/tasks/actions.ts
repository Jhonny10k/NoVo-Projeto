"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { createClient } from "@/lib/supabase/server";
import { requireFeature } from "@/lib/plans/entitlements";

function field(formData: FormData, key: string, max = 3000) {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

async function context() {
  await requireFeature("tasks");
  const organization = await requireCurrentOrganization();
  return { organization, supabase: await createClient() };
}

export async function createTaskAction(formData: FormData) {
  const { organization, supabase } = await context();
  const title = field(formData, "title", 200);
  const description = field(formData, "description", 3000);
  const priority = field(formData, "priority", 20);
  const dueAt = field(formData, "due_at", 40);
  const leadId = field(formData, "lead_id", 80);
  const customerId = field(formData, "customer_id", 80);
  const unitId = field(formData, "unit_id", 80) || null;
  if (title.length < 2 || !["low", "medium", "high", "urgent"].includes(priority)) redirect("/tarefas?erro=campos");

  const { data: claims } = await supabase.auth.getClaims();
  const { error } = await supabase.from("tasks").insert({
    organization_id: organization.id,
    unit_id: unitId,
    title,
    description: description || null,
    priority,
    due_at: dueAt ? new Date(dueAt).toISOString() : null,
    lead_id: leadId || null,
    customer_id: customerId || null,
    created_by: claims?.claims?.sub ?? null
  });
  if (error) redirect("/tarefas?erro=salvar");
  revalidatePath("/tarefas");
  revalidatePath("/dashboard");
  redirect("/tarefas?status=criada");
}

export async function updateTaskStatusAction(formData: FormData) {
  const { organization, supabase } = await context();
  const taskId = field(formData, "task_id", 80);
  const status = field(formData, "status", 30);
  if (!taskId || !["open", "in_progress", "done", "canceled"].includes(status)) redirect("/tarefas?erro=campos");
  const { error } = await supabase.from("tasks").update({ status }).eq("organization_id", organization.id).eq("id", taskId);
  if (error) redirect("/tarefas?erro=salvar");
  revalidatePath("/tarefas");
  revalidatePath("/dashboard");
}

export async function deleteTaskAction(formData: FormData) {
  const { organization, supabase } = await context();
  const taskId = field(formData, "task_id", 80);
  if (!taskId) redirect("/tarefas?erro=campos");
  const { error } = await supabase.from("tasks").delete().eq("organization_id", organization.id).eq("id", taskId);
  if (error) redirect("/tarefas?erro=permissao");
  revalidatePath("/tarefas");
  revalidatePath("/dashboard");
}
