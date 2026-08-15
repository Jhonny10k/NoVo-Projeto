import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { MercadoPagoPreapproval } from "@/lib/billing/mercadopago";

function providerAmountCents(resource: MercadoPagoPreapproval) {
  const raw = resource.auto_recurring?.transaction_amount;
  const number = typeof raw === "string" ? Number(raw) : raw;
  return typeof number === "number" && Number.isFinite(number) ? Math.round(number * 100) : null;
}

export async function syncMercadoPagoPreapproval(admin: SupabaseClient, resource: MercadoPagoPreapproval) {
  const sessionId = resource.external_reference;
  if (!sessionId) throw new Error("Assinatura sem external_reference reconhecível.");

  const { data: session, error: sessionError } = await admin
    .from("billing_checkout_sessions")
    .select("id,organization_id,plan_id,billing_cycle,amount_cents,provider_reference,status,coupon_id,discount_cents")
    .eq("id", sessionId)
    .eq("provider", "mercadopago")
    .maybeSingle();
  if (sessionError || !session) throw new Error("Checkout local não encontrado.");
  if (session.provider_reference && session.provider_reference !== resource.id) throw new Error("Referência do provider não corresponde ao checkout local.");

  const remoteAmount = providerAmountCents(resource);
  if (remoteAmount !== null && remoteAmount !== Number(session.amount_cents)) {
    throw new Error("Valor retornado pelo provider diverge do checkout local.");
  }
  if (resource.auto_recurring?.currency_id && resource.auto_recurring.currency_id !== "BRL") {
    throw new Error("Moeda inesperada retornada pelo provider.");
  }

  const normalizedStatus = resource.status.toLowerCase();
  const checkoutStatus = normalizedStatus === "authorized"
    ? "authorized"
    : ["cancelled", "canceled"].includes(normalizedStatus)
      ? "canceled"
      : "pending";

  await admin.from("billing_checkout_sessions").update({
    provider_reference: resource.id,
    status: checkoutStatus,
    error_message: null
  }).eq("id", session.id);

  if (checkoutStatus === "authorized" && session.coupon_id && Number(session.discount_cents) > 0) {
    const { error: redemptionError } = await admin.rpc("apply_coupon_redemption", { p_checkout_session_id: session.id });
    if (redemptionError) throw new Error(redemptionError.message);
  }

  const subscriptionStatus = normalizedStatus === "authorized"
    ? "active"
    : normalizedStatus === "paused"
      ? "suspended"
      : ["cancelled", "canceled"].includes(normalizedStatus)
        ? "canceled"
        : null;

  if (subscriptionStatus) {
    const { data: existing } = await admin
      .from("subscriptions")
      .select("id,status")
      .eq("provider", "mercadopago")
      .eq("provider_subscription_id", resource.id)
      .maybeSingle();

    const payload = {
      organization_id: session.organization_id,
      plan_id: session.plan_id,
      provider: "mercadopago",
      provider_customer_id: resource.payer_id == null ? null : String(resource.payer_id),
      provider_subscription_id: resource.id,
      provider_status: resource.status,
      status: subscriptionStatus,
      billing_cycle: session.billing_cycle,
      amount_cents: Number(session.amount_cents),
      current_period_end: resource.next_payment_date ?? null,
      last_provider_sync_at: new Date().toISOString()
    };

    let statusChanged = true;
    if (existing?.id) {
      statusChanged = existing.status !== subscriptionStatus;
      const { error } = await admin.from("subscriptions").update(payload).eq("id", existing.id);
      if (error) throw new Error(error.message);
    } else {
      const { error } = await admin.from("subscriptions").insert(payload);
      if (error) throw new Error(error.message);
    }

    if (statusChanged) {
      const { error } = await admin.from("events").insert({
        organization_id: session.organization_id,
        entity_type: "subscription",
        entity_id: existing?.id ?? null,
        event_type: "subscription_status_changed",
        metadata: { status: subscriptionStatus, provider: "mercadopago", provider_subscription_id: resource.id }
      });
      if (error) throw new Error(error.message);
    }
  }

  return { organizationId: session.organization_id, checkoutStatus, subscriptionStatus };
}
