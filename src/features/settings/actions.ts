"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { createClient } from "@/lib/supabase/server";
import { uploadOrganizationImage } from "@/lib/storage/images";

function field(formData: FormData, key: string, max: number) {
  const raw = formData.get(key);
  return typeof raw === "string" ? raw.trim().slice(0, max) : "";
}

export async function updateCompanySettingsAction(formData: FormData) {
  const organization = await requireCurrentOrganization();
  if (!["owner", "admin"].includes(organization.role)) redirect("/configuracoes?erro=permissao");
  const supabase = await createClient();
  const name = field(formData, "name", 120);
  const segment = field(formData, "segment", 120);
  const phone = field(formData, "phone", 40);
  const whatsapp = field(formData, "whatsapp", 40);
  const email = field(formData, "email", 200).toLowerCase();
  const city = field(formData, "city", 120);
  const state = field(formData, "state", 2).toUpperCase();
  const address = field(formData, "address", 300);
  const businessHours = field(formData, "business_hours", 1000);
  if (name.length < 2 || (state && state.length !== 2)) redirect("/configuracoes?erro=campos");

  const payload: Record<string, unknown> = {
    name, segment: segment || null, phone: phone || null, whatsapp: whatsapp || null,
    email: email || null, city: city || null, state: state || null, address: address || null,
    business_hours: businessHours || null, updated_at: new Date().toISOString()
  };
  const logo = formData.get("logo");
  if (logo instanceof File && logo.size > 0) {
    try {
      const image = await uploadOrganizationImage({ organizationId: organization.id, folder: "site", file: logo });
      payload.logo_url = image.publicUrl;
    } catch {
      redirect("/configuracoes?erro=imagem");
    }
  }
  const { error } = await supabase.from("organizations").update(payload).eq("id", organization.id);
  if (error) redirect("/configuracoes?erro=salvar");
  revalidatePath("/configuracoes");
  revalidatePath("/dashboard");
  revalidatePath("/site");
  redirect("/configuracoes?status=salvo");
}
