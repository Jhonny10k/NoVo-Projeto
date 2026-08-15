import Link from "next/link";
import { DashboardNav } from "@/components/dashboard/nav";
import { requireUser } from "@/lib/auth/require-user";
import { formatMoney } from "@/lib/format";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { hasFeature } from "@/lib/plans/entitlements";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
type Summary = { timezone:string; leads_today:number; leads_month:number; leads_previous_month:number; leads_total:number; potential_value_cents:number; customers_total:number|null; followups_due:number|null; quotes_pending:number|null; quotes_month:number|null; tasks_open:number|null; tasks_overdue:number|null; appointments_today:number|null };

export default async function DashboardPage() {
  await requireUser();
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();
  const [{ data: summaryData }, { data: siteConfig }, crm, quotes, tasks, appointments] = await Promise.all([
    supabase.rpc("organization_dashboard_summary",{p_organization_id:organization.id}),
    supabase.from("site_configs").select("status").eq("organization_id",organization.id).maybeSingle(),
    hasFeature("crm"), hasFeature("quotes"), hasFeature("tasks"), hasFeature("appointments")
  ]);
  const summary = (summaryData ?? { timezone:"America/Sao_Paulo",leads_today:0,leads_month:0,leads_previous_month:0,leads_total:0,potential_value_cents:0,customers_total:null,followups_due:null,quotes_pending:null,quotes_month:null,tasks_open:null,tasks_overdue:null,appointments_today:null }) as Summary;
  const leadDelta = summary.leads_month - summary.leads_previous_month;
  const sitePublished = siteConfig?.status === "published";
  const cards = [
    {label:"Novos leads hoje",value:summary.leads_today,href:"/crm",available:true},
    {label:"Follow-ups vencendo",value:summary.followups_due,href:"/crm",available:crm},
    {label:"Orçamentos pendentes",value:summary.quotes_pending,href:"/orcamentos",available:quotes},
    {label:"Tarefas atrasadas",value:summary.tasks_overdue,href:"/tarefas",available:tasks},
    {label:"Agendamentos hoje",value:summary.appointments_today,href:"/agenda",available:appointments}
  ];

  return <><DashboardNav organizationName={organization.name}/><main className="container-shell py-10">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-bold uppercase tracking-widest text-blue-700">Hoje</p><h1 className="mt-1 text-3xl font-black">O que precisa da sua atenção</h1><p className="muted mt-2">Dados reais da organização, calculados no timezone {summary.timezone}.</p></div>{sitePublished ? <Link href={`/empresa/${organization.slug}`} className="btn-secondary">Abrir site público</Link> : <Link href="/site" className="btn-primary">Configurar e publicar site</Link>}</div>
    <section className="mt-7 grid gap-4 sm:grid-cols-2 lg:grid-cols-5">{cards.map((card)=><article key={card.label} className="card p-5"><p className="muted text-sm">{card.label}</p>{card.available ? <><p className="mt-2 text-3xl font-black">{card.value ?? 0}</p><Link href={card.href} className="mt-3 inline-block text-sm font-bold text-blue-700">Abrir →</Link></> : <><p className="mt-2 text-xl font-black">Não incluído</p><Link href="/assinatura" className="mt-3 inline-block text-sm font-bold text-blue-700">Ver planos →</Link></>}</article>)}</section>
    <section className="mt-7 grid gap-4 lg:grid-cols-3"><article className="card p-5"><p className="muted text-sm">Leads neste mês</p><p className="mt-2 text-3xl font-black">{summary.leads_month}</p><p className={`mt-2 text-sm font-semibold ${leadDelta>=0?"text-emerald-700":"text-amber-700"}`}>{leadDelta>=0?"+":""}{leadDelta} em relação ao mês anterior ({summary.leads_previous_month})</p></article><article className="card p-5"><p className="muted text-sm">Valor potencial aberto</p><p className="mt-2 text-3xl font-black">{formatMoney(summary.potential_value_cents)}</p><p className="muted mt-2 text-xs">Soma dos valores informados nos leads que ainda não foram fechados/perdidos.</p></article><article className="card p-5"><p className="muted text-sm">Total de leads</p><p className="mt-2 text-3xl font-black">{summary.leads_total}</p>{crm && summary.customers_total!==null ? <p className="muted mt-2 text-sm">Clientes convertidos: <strong>{summary.customers_total}</strong></p> : null}</article></section>
    <section className="card mt-7 p-6"><h2 className="text-xl font-black">Ações rápidas</h2><div className="mt-4 flex flex-wrap gap-2"><Link href="/crm" className="btn-primary">Novo lead</Link>{quotes ? <Link href="/orcamentos" className="btn-secondary">Novo orçamento</Link> : null}{tasks ? <Link href="/tarefas" className="btn-secondary">Nova tarefa</Link> : null}{appointments ? <Link href="/agenda" className="btn-secondary">Novo agendamento</Link> : null}<Link href="/catalogo" className="btn-secondary">Catálogo</Link></div></section>
  </main></>;
}
