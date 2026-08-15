"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/require-user";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { createClient } from "@/lib/supabase/server";
import { uploadOrganizationImage } from "@/lib/storage/images";

function field(formData: FormData, key: string, max: number) {
  const raw = formData.get(key);
  return typeof raw === "string" ? raw.trim().slice(0, max) : "";
}

export async function updateProfileAction(formData: FormData) {
  const user = await requireUser();
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();
  const fullName = field(formData, "full_name", 120);
  const phone = field(formData, "phone", 40);
  const jobTitle = field(formData, "job_title", 100);
  if (fullName.length < 2) redirect("/perfil?erro=nome");

  const notificationPreferences = {
    leads: formData.get("notify_leads") === "on",
    quotes: formData.get("notify_quotes") === "on",
    appointments: formData.get("notify_appointments") === "on",
    billing: formData.get("notify_billing") === "on"
  };

  const payload: Record<string, unknown> = {
    full_name: fullName,
    phone: phone || null,
    job_title: jobTitle || null,
    notification_preferences: notificationPreferences,
    updated_at: new Date().toISOString()
  };

  const avatar = formData.get("avatar");
  if (avatar instanceof File && avatar.size > 0) {
    try {
      const image = await uploadOrganizationImage({ organizationId: organization.id, folder: "profile", file: avatar });
      payload.avatar_url = image.publicUrl;
    } catch {
      redirect("/perfil?erro=imagem");
    }
  }

  const { error } = await supabase.from("profiles").update(payload).eq("id", user.id);
  if (error) redirect("/perfil?erro=salvar");
  revalidatePath("/perfil");
  redirect("/perfil?status=salvo");
}
