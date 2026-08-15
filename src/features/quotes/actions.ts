"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { parseMoneyToCents } from "@/lib/format";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { consumeRateLimit, requestFingerprint } from "@/lib/security/rate-limit";
import { createClient } from "@/lib/supabase/server";
import { requireFeature } from "@/lib/plans/entitlements";

function field(formData: FormData, key: string, max = 5000) {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

export async function createQuoteAction(formData: FormData) {
  await requireFeature("quotes");
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();

  const leadId = field(formData, "lead_id", 80) || null;
  const customerId = field(formData, "customer_id", 80) || null;
  const descriptions = formData.getAll("item_description").map((v) => typeof v === "string" ? v.trim().slice(0, 1000) : "");
  const quantities = formData.getAll("item_quantity").map((v) => typeof v === "string" ? Number(v.replace(",", ".")) : 0);
  const prices = formData.getAll("item_unit_price").map((v) => typeof v === "string" ? parseMoneyToCents(v) : null);
  const types = formData.getAll("item_type").map((v) => typeof v === "string" ? v : "custom");
  const refs = formData.getAll("item_reference_id").map((v) => typeof v === "string" ? v : "");

  const items = descriptions.map((description, index) => ({
    item_type: ["product", "service", "custom"].includes(types[index]) ? types[index] : "custom",
    reference_id: refs[index] || null,
    description,
    quantity: Number.isFinite(quantities[index]) && quantities[index] > 0 ? quantities[index] : 1,
    unit_price_cents: prices[index] ?? 0
  })).filter((item) => item.description.length > 0);

  if (items.length === 0 || (!leadId && !customerId)) redirect("/orcamentos?erro=campos");

  const discountCents = parseMoneyToCents(field(formData, "discount", 40)) ?? 0;
  const feeCents = parseMoneyToCents(field(formData, "fee", 40)) ?? 0;
  const validUntil = field(formData, "valid_until", 20) || null;
  const notes = field(formData, "notes", 5000) || null;

  const { data, error } = await supabase.rpc("create_quote_with_items", {
    p_organization_id: organization.id,
    p_lead_id: leadId,
    p_customer_id: customerId,
    p_notes: notes,
    p_valid_until: validUntil,
    p_discount_cents: discountCents,
    p_fee_cents: feeCents,
    p_items: items
  });

  if (error || !data) redirect("/orcamentos?erro=salvar");
  revalidatePath("/orcamentos");
  redirect(`/orcamentos/${data}?status=criado`);
}

export async function publishQuoteAction(formData: FormData) {
  await requireFeature("quotes");
  const organization = await requireCurrentOrganization();
  const quoteId = field(formData, "quote_id", 80);
  if (!quoteId) redirect("/orcamentos?erro=campos");
  const supabase = await createClient();
  const { error } = await supabase.rpc("publish_quote_link", { p_organization_id: organization.id, p_quote_id: quoteId });
  if (error) redirect(`/orcamentos/${quoteId}?erro=publicar`);
  revalidatePath(`/orcamentos/${quoteId}`);
  redirect(`/orcamentos/${quoteId}?status=publicado`);
}

export async function respondPublicQuoteAction(token: string, response: "approved" | "rejected" | "change_requested") {
  let allowed = false;
  try {
    const identifierHash = await requestFingerprint(token);
    const rate = await consumeRateLimit({ scope: "public_quote_response", identifierHash, limit: 12, windowSeconds: 900 });
    allowed = rate.allowed;
  } catch {
    redirect(`/orcamento/${token}?erro=seguranca`);
  }
  if (!allowed) redirect(`/orcamento/${token}?erro=limite`);

  const supabase = await createClient();
  const { error } = await supabase.rpc("respond_public_quote", { p_token: token, p_response: response });
  if (error) redirect(`/orcamento/${token}?erro=resposta`);
  revalidatePath(`/orcamento/${token}`);
  redirect(`/orcamento/${token}?status=${response}`);
}
