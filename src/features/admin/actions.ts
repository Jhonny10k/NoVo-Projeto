"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { parseMoneyToCents } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import { featureCodes } from "@/lib/plans/entitlements";

function field(formData: FormData, key: string, max = 2000) {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

export async function setOrganizationStatusAction(formData: FormData) {
  const organizationId = field(formData, "organization_id", 80);
  const status = field(formData, "status", 20);
  if (!organizationId || !["active", "suspended", "canceled"].includes(status)) redirect("/admin?erro=campos");
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_organization_status", { p_organization_id: organizationId, p_status: status });
  if (error) redirect("/admin?erro=permissao");
  revalidatePath("/admin");
}

export async function updatePlanAction(formData: FormData) {
  const planId = field(formData, "plan_id", 80);
  const name = field(formData, "name", 100);
  const description = field(formData, "description", 500);
  const monthly = parseMoneyToCents(field(formData, "monthly", 40));
  const annual = parseMoneyToCents(field(formData, "annual", 40));
  const active = formData.get("active") === "on";
  const trialDays = Number(field(formData, "trial_days", 3));
  const entitlements = Object.fromEntries(featureCodes.map((code) => [code, formData.get(`feature_${code}`) === "on"]));
  const numericLimits = {
    api_keys: Number(field(formData,"limit_api_keys",8)||"3"),
    api_requests_per_hour: Number(field(formData,"limit_api_requests_per_hour",10)||"1000"),
    webhook_endpoints: Number(field(formData,"limit_webhook_endpoints",8)||"3"),
    custom_domains: Number(field(formData,"limit_custom_domains",8)||"1"),
    units: Number(field(formData,"limit_units",8)||"5")
  };
  if (!planId || name.length < 2 || monthly == null || annual == null || !Number.isInteger(trialDays) || trialDays < 0 || trialDays > 90 || Object.values(numericLimits).some(v=>!Number.isInteger(v)||v<0||v>100000000)) redirect("/admin?erro=plano");
  const supabase = await createClient();
  const [{ error }, { error: entitlementError }, { error: limitsError }] = await Promise.all([
    supabase.rpc("admin_update_plan", { p_plan_id: planId, p_name: name, p_description: description, p_price_monthly_cents: monthly, p_price_annual_cents: annual, p_active: active }),
    supabase.rpc("admin_update_plan_entitlements", { p_plan_id: planId, p_entitlements: entitlements, p_trial_days: trialDays }),
    supabase.rpc("admin_update_plan_limits", {p_plan_id:planId,p_limits:numericLimits})
  ]);
  if (error || entitlementError || limitsError) redirect("/admin?erro=permissao");
  revalidatePath("/admin");
  revalidatePath("/planos");
  redirect("/admin?status=plano-salvo");
}

export async function saveCouponAction(formData: FormData) {
  const couponId = field(formData, "coupon_id", 80) || null;
  const code = field(formData, "code", 40).toUpperCase();
  const description = field(formData, "description", 500);
  const discountType = field(formData, "discount_type", 20);
  const percentRaw = Number(field(formData, "percent_off", 4));
  const amountRaw = parseMoneyToCents(field(formData, "amount_off", 40));
  const startsAtRaw = field(formData, "starts_at", 40);
  const expiresAtRaw = field(formData, "expires_at", 40);
  const maxRaw = field(formData, "max_redemptions", 10);
  const perOrgRaw = Number(field(formData, "per_organization_limit", 10) || "1");
  const planId = field(formData, "plan_id", 80) || null;
  const active = formData.get("active") === "on";

  const percentOff = discountType === "percent" && Number.isInteger(percentRaw) ? percentRaw : null;
  const amountOffCents = discountType === "fixed" ? amountRaw : null;
  const maxRedemptions = maxRaw ? Number(maxRaw) : null;
  const startsAt = startsAtRaw ? new Date(startsAtRaw).toISOString() : null;
  const expiresAt = expiresAtRaw ? new Date(expiresAtRaw).toISOString() : null;

  if (!/^[A-Z0-9_-]{3,40}$/.test(code) || !["percent", "fixed"].includes(discountType) || !Number.isInteger(perOrgRaw) || perOrgRaw < 1) redirect("/admin?erro=cupom");
  if (maxRedemptions !== null && (!Number.isInteger(maxRedemptions) || maxRedemptions < 1)) redirect("/admin?erro=cupom");
  if ((discountType === "percent" && (percentOff === null || percentOff < 1 || percentOff > 100)) || (discountType === "fixed" && (amountOffCents === null || amountOffCents <= 0))) redirect("/admin?erro=cupom");

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_save_coupon", {
    p_coupon_id: couponId, p_code: code, p_description: description, p_discount_type: discountType,
    p_percent_off: percentOff, p_amount_off_cents: amountOffCents, p_starts_at: startsAt, p_expires_at: expiresAt,
    p_max_redemptions: maxRedemptions, p_per_organization_limit: perOrgRaw, p_plan_id: planId, p_active: active
  });
  if (error) redirect("/admin?erro=cupom");
  revalidatePath("/admin");
  redirect("/admin?status=cupom-salvo");
}
