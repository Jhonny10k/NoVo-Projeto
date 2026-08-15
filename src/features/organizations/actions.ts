"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function value(formData: FormData, key: string) {
  const item = formData.get(key);
  return typeof item === "string" ? item.trim() : "";
}

export async function createOrganizationAction(formData: FormData) {
  const name = value(formData, "name");
  const segment = value(formData, "segment");
  const phone = value(formData, "phone");
  const whatsapp = value(formData, "whatsapp");
  const city = value(formData, "city");
  const state = value(formData, "state").toUpperCase();

  if (name.length < 2 || segment.length < 2 || city.length < 2 || state.length !== 2) {
    redirect("/onboarding?erro=campos");
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_organization_with_owner", {
    p_name: name,
    p_segment: segment,
    p_phone: phone || null,
    p_whatsapp: whatsapp || null,
    p_city: city,
    p_state: state
  });

  if (error) redirect("/onboarding?erro=salvar");
  redirect("/dashboard");
}
