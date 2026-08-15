import Link from "next/link";
import { DashboardNav } from "@/components/dashboard/nav";
import { cancelSubscriptionAction, startSubscriptionCheckoutAction, syncSubscriptionAction } from "@/features/billing/actions";
import { requireUser } from "@/lib/auth/require-user";
import { getBillingAvailability } from "@/lib/billing/provider";
import { formatMoney } from "@/lib/format";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { createClient } from "@/lib/supabase/server";
import { featureLabels, type FeatureCode } from "@/lib/plans/entitlements";

export const dynamic = "force-dynamic";
type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };
type Plan = { id: string; name: string; description: string | null; price_monthly_cents: number; price_annual_cents: number; features: unknown };
type Subscription = { status: string; billing_cycle: string | null; provider: string; provider_status: string | null; current_period_end: string | null; trial_ends_at: string | null; plans: { name: string } | { name: string }[] | null };
type Checkout = { status: string; checkout_url: string | null; created_at: string; plans: { name: string } | { name: string }[] | null };

export default async function SubscriptionPage({ searchParams }: Props) {
  await requireUser();
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();
  const params = await searchParams;
  const [{ data: subscription }, { data: plans }, { data: checkout }] = await Promise.all([
    supabase.from("subscriptions").select("status,billing_cycle,provider,provider_status,current_period_end,trial_ends_at,plans(name)").eq("organization_id", organization.id).order("created_at", { ascending: false }).limit(1).maybeSingle(),
    supabase.from("plans").select("id,name,description,price_monthly_cents,price_annual_cents,features").eq("active", true).order("sort_order"),
    supabase.from("billing_checkout_sessions").select("status,checkout_url,created_at,plans(name)").eq("organization_id", organization.id).order("created_at", { ascending: false }).limit(1).maybeSingle()
  ]);
  const billing = getBillingAvailability();
  const canManage = ["owner", "admin"].includes(organization.role);
  const status = typeof params.status === "string" ? params.status : "";
  const error = typeof params.erro === "string" ? params.erro : "";
  const requestedFeature = typeof params.recurso === "string" ? params.recurso as FeatureCode : null;
  const current = subscription as Subscription | null;
  const lastCheckout = checkout as Checkout | null;
  const currentPlan = current?.plans ? (Array.isArray(current.plans) ? current.plans[0] : current.plans) : null;
  const checkoutPlan = lastCheckout?.plans ? (Array.isArray(lastCheckout.plans) ? lastCheckout.plans[0] : lastCheckout.plans) : null;
  const hasBlockingSubscription = Boolean(current && ["active", "past_due", "suspended"].includes(current.status));
  const hasPendingCheckout = Boolean(lastCheckout && ["creating", "pending"].includes(lastCheckout.status));

  return <><DashboardNav organizationName={organization.name} /><main className="container-shell py-10">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-bold uppercase tracking-widest text-blue-700">Assinatura</p><h1 className="mt-1 text-3xl font-black">Plano da empresa</h1><p className="muted mt-2">Cobrança e status vêm do provider real; nenhum pagamento é aprovado localmente por suposição.</p></div><Link href="/planos" className="btn-secondary">Página pública de planos</Link></div>

    {requestedFeature && featureLabels[requestedFeature] ? <section className="mt-5 rounded-2xl border border-blue-200 bg-blue-50 p-5"><p className="text-sm font-black text-blue-900">Recurso disponível em outro plano</p><p className="mt-1 text-sm text-blue-900">Sua assinatura atual não inclui <strong>{featureLabels[requestedFeature]}</strong>. Compare os planos abaixo para liberar o recurso.</p></section> : null}
    {status ? <p className="mt-5 rounded-xl bg-emerald-50 p-4 text-sm font-semibold">Assinatura atualizada com o provider.</p> : null}
    {error ? <p role="alert" className="mt-5 rounded-xl bg-amber-50 p-4 text-sm">{error === "assinatura-ativa" ? "Já existe uma assinatura ativa. Cancele ou trate a troca de plano antes de criar outra cobrança." : error === "limite" ? "Muitas tentativas de checkout. Tente novamente mais tarde." : error === "cupom" ? "Cupom inválido, expirado, incompatível com o plano ou já utilizado por esta empresa." : "Não foi possível concluir a operação de cobrança. Verifique a configuração e tente novamente."}</p> : null}

    <section className="card mt-7 p-6">
      <h2 className="font-black">Situação atual</h2>
      {current ? <div className="mt-3 grid gap-1 text-sm"><p>Plano: <strong>{currentPlan?.name ?? "—"}</strong></p><p>Status local: <strong>{current.status}</strong></p><p>Provider: <strong>{current.provider}</strong>{current.provider_status ? ` · ${current.provider_status}` : ""}</p>{current.status === "trial" && current.trial_ends_at ? <p>Trial até: <strong>{new Intl.DateTimeFormat("pt-BR", { dateStyle: "medium" }).format(new Date(current.trial_ends_at))}</strong></p> : null}{current.current_period_end ? <p>Próxima referência de cobrança: <strong>{new Intl.DateTimeFormat("pt-BR", { dateStyle: "medium" }).format(new Date(current.current_period_end))}</strong></p> : null}</div> : <p className="muted mt-2">Nenhuma assinatura ativa registrada para esta organização.</p>}
      <p className={`mt-4 rounded-xl p-4 text-sm ${billing.configured ? "bg-emerald-50" : "bg-amber-50"}`}>{billing.message}</p>
      {canManage && current && ["active","past_due","suspended"].includes(current.status) && current.provider === "mercadopago" ? <form action={cancelSubscriptionAction} className="mt-4"><button className="btn-danger" type="submit">Cancelar assinatura no Mercado Pago</button></form> : null}
    </section>

    {lastCheckout && ["creating","pending"].includes(lastCheckout.status) ? <section className="card mt-5 p-6"><h2 className="font-black">Checkout pendente</h2><p className="muted mt-2 text-sm">{checkoutPlan?.name ?? "Plano"} · status {lastCheckout.status}</p><div className="mt-4 flex flex-wrap gap-2">{lastCheckout.checkout_url ? <a className="btn-primary" href={lastCheckout.checkout_url}>Continuar no Mercado Pago</a> : null}{canManage ? <form action={syncSubscriptionAction}><button className="btn-secondary" type="submit">Atualizar status</button></form> : null}</div></section> : null}

    <section className="mt-8 grid gap-4 lg:grid-cols-3">{((plans ?? []) as Plan[]).map((plan) => <article className="card p-5" key={plan.id}><h2 className="text-xl font-black">{plan.name}</h2><p className="muted mt-2 text-sm">{plan.description}</p><p className="mt-5 text-2xl font-black">{formatMoney(plan.price_monthly_cents)}<span className="muted text-sm font-normal">/mês</span></p><p className="muted mt-1 text-xs">Anual: {formatMoney(plan.price_annual_cents)}</p>{canManage && billing.configured && !hasBlockingSubscription && !hasPendingCheckout ? <div className="mt-5 grid gap-3"><p className="muted text-xs">Cupom é opcional e é validado no servidor. O resgate só é consumido após a autorização real da assinatura.</p><div className="grid grid-cols-1 gap-2 sm:grid-cols-2"><form action={startSubscriptionCheckoutAction} className="grid gap-2"><input type="hidden" name="plan_id" value={plan.id} /><input type="hidden" name="billing_cycle" value="monthly" /><label className="field"><span className="text-xs">Cupom</span><input name="coupon_code" maxLength={40} placeholder="Opcional" autoCapitalize="characters" /></label><button className="btn-primary w-full" type="submit">Assinar mensal</button></form><form action={startSubscriptionCheckoutAction} className="grid gap-2"><input type="hidden" name="plan_id" value={plan.id} /><input type="hidden" name="billing_cycle" value="annual" /><label className="field"><span className="text-xs">Cupom</span><input name="coupon_code" maxLength={40} placeholder="Opcional" autoCapitalize="characters" /></label><button className="btn-secondary w-full" type="submit">Assinar anual</button></form></div></div> : <p className="mt-5 rounded-lg bg-black/5 p-3 text-xs">{billing.configured ? "Checkout disponível ao proprietário/administrador quando não houver assinatura ou checkout pendente." : "Checkout indisponível até configurar o gateway."}</p>}</article>)}</section>
  </main></>;
}
