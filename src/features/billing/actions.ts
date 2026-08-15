"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/require-user";
import { getBillingAvailability } from "@/lib/billing/provider";
import { cancelMercadoPagoPreapproval, createMercadoPagoSubscription, getMercadoPagoPreapproval } from "@/lib/billing/mercadopago";
import { syncMercadoPagoPreapproval } from "@/lib/billing/sync";
import { getPublicAppUrl } from "@/lib/env";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { consumeRateLimit, requestFingerprint } from "@/lib/security/rate-limit";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

function text(formData: FormData, key: string, max = 120) {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

async function billingContext() {
  const user = await requireUser();
  const organization = await requireCurrentOrganization();
  if (!["owner", "admin"].includes(organization.role)) redirect("/assinatura?erro=permissao");
  if (!user.email) redirect("/assinatura?erro=email");
  return { user, organization };
}

export async function startSubscriptionCheckoutAction(formData: FormData) {
  const { user, organization } = await billingContext();
  const planId = text(formData, "plan_id", 80);
  const billingCycle = text(formData, "billing_cycle", 20);
  const couponCode = text(formData, "coupon_code", 40).toUpperCase();
  if (!planId || !["monthly", "annual"].includes(billingCycle)) redirect("/assinatura?erro=campos");

  const availability = getBillingAvailability();
  if (!availability.configured || availability.provider !== "mercadopago") redirect("/assinatura?erro=gateway");

  let rateAllowed = false;
  try {
    const identifierHash = await requestFingerprint(`${user.id}:${organization.id}`);
    const rate = await consumeRateLimit({ scope: "billing_checkout", identifierHash, limit: 5, windowSeconds: 3600 });
    rateAllowed = rate.allowed;
  } catch {
    redirect("/assinatura?erro=seguranca");
  }
  if (!rateAllowed) redirect("/assinatura?erro=limite");

  const supabase = await createClient();
  const [{ data: plan }, { data: activeSubscription }] = await Promise.all([
    supabase.from("plans").select("id,name,price_monthly_cents,price_annual_cents").eq("id", planId).eq("active", true).maybeSingle(),
    supabase.from("subscriptions").select("id,status").eq("organization_id", organization.id).in("status", ["active", "past_due", "suspended"]).order("created_at", { ascending: false }).limit(1).maybeSingle()
  ]);
  if (!plan) redirect("/assinatura?erro=plano");
  if (activeSubscription) redirect("/assinatura?erro=assinatura-ativa");

  const admin = createAdminClient();
  const { data: pending } = await admin
    .from("billing_checkout_sessions")
    .select("id,checkout_url,status")
    .eq("organization_id", organization.id)
    .in("status", ["creating", "pending"])
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (pending?.checkout_url?.startsWith("https://")) redirect(pending.checkout_url);
  if (pending) redirect("/assinatura?erro=checkout-pendente");

  const listAmountCents = billingCycle === "annual" ? Number(plan.price_annual_cents) : Number(plan.price_monthly_cents);
  if (!Number.isSafeInteger(listAmountCents) || listAmountCents <= 0) redirect("/assinatura?erro=preco");

  let amountCents = listAmountCents;
  let discountCents = 0;
  let couponId: string | null = null;
  if (couponCode) {
    const { data: coupon, error: couponError } = await supabase.rpc("validate_coupon_for_checkout", {
      p_organization_id: organization.id,
      p_plan_id: plan.id,
      p_code: couponCode,
      p_list_amount_cents: listAmountCents
    });
    if (couponError || !coupon || typeof coupon !== "object") redirect("/assinatura?erro=cupom");
    const validated = coupon as { id?: unknown; discount_cents?: unknown; final_amount_cents?: unknown };
    couponId = typeof validated.id === "string" ? validated.id : null;
    discountCents = Number(validated.discount_cents);
    amountCents = Number(validated.final_amount_cents);
    if (!couponId || !Number.isSafeInteger(discountCents) || discountCents <= 0 || !Number.isSafeInteger(amountCents) || amountCents <= 0) redirect("/assinatura?erro=cupom");
  }

  const sessionId = randomUUID();
  const { error: sessionError } = await admin.from("billing_checkout_sessions").insert({
    id: sessionId,
    organization_id: organization.id,
    plan_id: plan.id,
    billing_cycle: billingCycle,
    provider: "mercadopago",
    payer_email: user.email,
    amount_cents: amountCents,
    list_amount_cents: listAmountCents,
    discount_cents: discountCents,
    coupon_id: couponId,
    status: "creating",
    created_by: user.id
  });
  if (sessionError) redirect("/assinatura?erro=checkout-pendente");

  let checkoutUrl: string | null = null;
  try {
    const result = await createMercadoPagoSubscription({
      sessionId,
      payerEmail: user.email,
      reason: `${plan.name} — ${organization.name}`,
      amountCents,
      billingCycle: billingCycle as "monthly" | "annual",
      backUrl: `${getPublicAppUrl()}/assinatura?retorno=mercadopago`
    });
    checkoutUrl = result.checkoutUrl;
    const { error } = await admin.from("billing_checkout_sessions").update({
      provider_reference: result.resource.id,
      checkout_url: checkoutUrl,
      status: result.resource.status === "authorized" ? "authorized" : "pending"
    }).eq("id", sessionId);
    if (error) throw new Error(error.message);

    if (result.resource.status === "authorized") {
      await syncMercadoPagoPreapproval(admin, result.resource);
    }
  } catch (error) {
    await admin.from("billing_checkout_sessions").update({
      status: "failed",
      error_message: error instanceof Error ? error.message.slice(0, 500) : "Falha desconhecida"
    }).eq("id", sessionId);
    redirect("/assinatura?erro=provider");
  }

  if (!checkoutUrl) redirect("/assinatura?erro=provider");
  redirect(checkoutUrl);
}

export async function syncSubscriptionAction() {
  const { organization } = await billingContext();
  const admin = createAdminClient();
  const { data: session } = await admin
    .from("billing_checkout_sessions")
    .select("id,provider_reference")
    .eq("organization_id", organization.id)
    .eq("provider", "mercadopago")
    .in("status", ["pending", "authorized"])
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!session?.provider_reference) redirect("/assinatura?erro=sem-checkout");

  try {
    const resource = await getMercadoPagoPreapproval(session.provider_reference);
    await syncMercadoPagoPreapproval(admin, resource);
  } catch {
    redirect("/assinatura?erro=sincronizar");
  }
  revalidatePath("/assinatura");
  redirect("/assinatura?status=sincronizado");
}

export async function cancelSubscriptionAction() {
  const { organization } = await billingContext();
  const supabase = await createClient();
  const { data: subscription } = await supabase
    .from("subscriptions")
    .select("id,provider,provider_subscription_id")
    .eq("organization_id", organization.id)
    .in("status", ["active", "past_due", "suspended"])
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!subscription?.provider_subscription_id || subscription.provider !== "mercadopago") redirect("/assinatura?erro=cancelar");

  const admin = createAdminClient();
  try {
    const resource = await cancelMercadoPagoPreapproval(subscription.provider_subscription_id);
    await syncMercadoPagoPreapproval(admin, resource);
  } catch {
    redirect("/assinatura?erro=cancelar");
  }
  revalidatePath("/assinatura");
  redirect("/assinatura?status=cancelada");
}
