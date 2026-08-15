"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { createClient } from "@/lib/supabase/server";

function value(formData: FormData, key: string, max = 80) {
  const item = formData.get(key);
  return typeof item === "string" ? item.trim().slice(0, max) : "";
}

export async function markNotificationReadAction(formData: FormData) {
  const organization = await requireCurrentOrganization();
  const notificationId = value(formData, "notification_id") || null;
  const supabase = await createClient();
  const { error } = await supabase.rpc("mark_notifications_read", {
    p_organization_id: organization.id,
    p_notification_id: notificationId
  });
  if (error) redirect("/notificacoes?erro=salvar");
  revalidatePath("/notificacoes");
}

export async function markAllNotificationsReadAction() {
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();
  const { error } = await supabase.rpc("mark_notifications_read", {
    p_organization_id: organization.id,
    p_notification_id: null
  });
  if (error) redirect("/notificacoes?erro=salvar");
  revalidatePath("/notificacoes");
  redirect("/notificacoes?status=lidas");
}
