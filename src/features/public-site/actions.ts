"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { consumeRateLimit, requestFingerprint } from "@/lib/security/rate-limit";

function field(formData: FormData, name: string) {
  const value = formData.get(name);
  return typeof value === "string" ? value.trim() : "";
}

export async function submitQuoteRequestAction(slug: string, formData: FormData) {
  const name = field(formData, "name");
  const whatsapp = field(formData, "whatsapp");
  const email = field(formData, "email").toLowerCase();
  const description = field(formData, "description");
  const website = field(formData, "website");
  const utmSource = field(formData, "utm_source").slice(0,120);
  const utmMedium = field(formData, "utm_medium").slice(0,120);
  const utmCampaign = field(formData, "utm_campaign").slice(0,160);
  const utmContent = field(formData, "utm_content").slice(0,160);
  const utmTerm = field(formData, "utm_term").slice(0,160);

  if (name.length < 2 || (!whatsapp && !email) || description.length < 5) {
    redirect(`/empresa/${slug}?orcamento=erro`);
  }

  let rateAllowed = false;
  try {
    const identifierHash = await requestFingerprint(slug);
    const rate = await consumeRateLimit({ scope: "public_quote_request", identifierHash, limit: 10, windowSeconds: 900 });
    rateAllowed = rate.allowed;
  } catch {
    redirect(`/empresa/${slug}?orcamento=erro`);
  }
  if (!rateAllowed) redirect(`/empresa/${slug}?orcamento=limite`);

  const supabase = await createClient();
  const { error } = await supabase.rpc("public_create_quote_request", {
    p_organization_slug: slug,
    p_name: name,
    p_whatsapp: whatsapp || null,
    p_email: email || null,
    p_description: description,
    p_honeypot: website || null,
    p_utm_source: utmSource || null,
    p_utm_medium: utmMedium || null,
    p_utm_campaign: utmCampaign || null,
    p_utm_content: utmContent || null,
    p_utm_term: utmTerm || null
  });

  if (error) redirect(`/empresa/${slug}?orcamento=erro`);
  redirect(`/empresa/${slug}?orcamento=recebido`);
}
