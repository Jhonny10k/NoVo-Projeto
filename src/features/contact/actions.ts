"use server";

import { redirect } from "next/navigation";
import { consumeRateLimit, requestFingerprint } from "@/lib/security/rate-limit";
import { createAdminClient } from "@/lib/supabase/admin";

function field(formData: FormData, key: string, max: number) {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim().slice(0,max) : "";
}

export async function submitCommercialContactAction(formData: FormData) {
  const name = field(formData,"name",160);
  const email = field(formData,"email",254).toLowerCase();
  const phone = field(formData,"phone",80);
  const message = field(formData,"message",5000);
  const website = field(formData,"website",200);
  if (website) redirect("/contato?status=recebido");
  if (name.length < 2 || !email.includes("@") || message.length < 5) redirect("/contato?erro=campos");

  try {
    const identifierHash = await requestFingerprint(email);
    const rate = await consumeRateLimit({ scope:"public_commercial_contact", identifierHash, limit:5, windowSeconds:3600 });
    if (!rate.allowed) redirect("/contato?erro=limite");
  } catch {
    redirect("/contato?erro=seguranca");
  }

  const admin = createAdminClient();
  const { error } = await admin.from("platform_contact_messages").insert({ name, email, phone: phone || null, message });
  if (error) redirect("/contato?erro=salvar");
  redirect("/contato?status=recebido");
}
