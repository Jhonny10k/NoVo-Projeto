import Link from "next/link";
import { DashboardNav } from "@/components/dashboard/nav";
import { requireUser } from "@/lib/auth/require-user";
import { formatMoney } from "@/lib/format";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { hasFeature } from "@/lib/plans/entitlements";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Summary = {
  timezone: string;
  leads_today: number;
  leads_month: number;
  leads_previous_month: number;
  leads_total: number;
  potential_value_cents: number;
  customers_total: number | null;
  followups_due: number | null;
  quotes_pending: number | null;
  quotes_month: number | null;
  tasks_open: number | null;
  tasks_overdue: number | null;
  appointments_today: number | null;
};

type AttentionCard = {
  label: string;
  description: string;
  value: number | null;
  href: string;
  available: boolean;
};

const defaultSummary: Summary = {
  timezone: "America/Sao_Paulo",
  leads_today: 0,
  leads_month: 0,
  leads_previous_month: 0,
  leads_total: 0,
  potential_value_cents: 0,
  customers_total: null,
  followups_due: null,
  quotes_pending: null,
  quotes_month: null,
  tasks_open: null,
  tasks_overdue: null,
  appointments_today: null
};

export default async function DashboardPage() {
  await requireUser();
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();

  const [{ data: summaryData }, { data: siteConfig }, crm, quotes, tasks, appointments] = await Promise.all([
    supabase.rpc("organization_dashboard_summary", { p_organization_id: organization.id }),
    supabase.from("site_configs").select("status").eq("organization_id", organization.id).maybeSingle(),
    hasFeature("crm"),
    hasFeature("quotes"),
    hasFeature("tasks"),
    hasFeature("appointments")
  ]);

  const summary = (summaryData ?? defaultSummary) as Summary;
  const leadDelta = summary.leads_month - summary.leads_previous_month;
  const sitePublished = siteConfig?.status === "published";

  const attentionCards: AttentionCard[] = [
    {
      label: "Novos leads hoje",
      description: "Entradas que chegaram hoje",
      value: summary.leads_today,
      href: "/crm",
      available: true
    },
    {
      label: "Follow-ups vencendo",
      description: "Contatos que pedem retorno",
      value: summary.followups_due,
      href: "/crm",
      available: crm
    },
    {
      label: "Orçamentos pendentes",
      description: "Propostas aguardando avanço",
      value: summary.quotes_pending,
      href: "/orcamentos",
      available: quotes
    },
    {
      label: "Tarefas atrasadas",
      description: "Pendências fora do prazo",
      value: summary.tasks_overdue,
      href: "/tarefas",
      available: tasks
    },
    {
      label: "Agendamentos hoje",
      description: "Compromissos desta data",
      value: summary.appointments_today,
      href: "/agenda",
      available: appointments
    }
  ];

  const quickActions = [
    { label: "Abrir CRM", description: "Leads e oportunidades", href: "/crm", available: true },
    { label: "Criar orçamento", description: "Propostas e negociações", href: "/orcamentos", available: quotes },
    { label: "Organizar tarefas", description: "Pendências e próximos passos", href: "/tarefas", available: tasks },
    { label: "Abrir agenda", description: "Horários e atendimentos", href: "/agenda", available: appointments },
    { label: "Gerenciar catálogo", description: "Produtos e serviços", href: "/catalogo", available: true },
    { label: "Ver atendimento", description: "Conversas centralizadas", href: "/atendimento", available: true }
  ].filter((action) => action.available);

  return (
    <>
      <DashboardNav organizationName={organization.name} />
      <main className="container-shell pb-14 pt-7 sm:pt-10">
        <section className="dashboard-hero">
          <div className="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
            <div className="max-w-3xl">
              <p className="eyebrow">Visão geral</p>
              <h1 className="page-title mt-4">O que merece sua atenção hoje</h1>
              <p className="muted mt-3 max-w-2xl text-[.96rem] leading-7 sm:text-base">
                Uma leitura rápida da operação para você decidir o próximo passo sem procurar informação em vários módulos.
              </p>
              <p className="mt-3 text-xs font-semibold text-slate-400">Timezone da organização: {summary.timezone}</p>
            </div>
            <div className="flex w-full flex-col gap-2 sm:w-auto sm:flex-row">
              {sitePublished ? (
                <Link href={`/empresa/${organization.slug}`} className="btn-secondary w-full sm:w-auto">Abrir site público</Link>
              ) : (
                <Link href="/site" className="btn-primary w-full sm:w-auto">Configurar site</Link>
              )}
              <Link href="/notificacoes" className="btn-secondary w-full sm:w-auto">Notificações</Link>
            </div>
          </div>
        </section>

        <section className="mt-7" aria-labelledby="attention-title">
          <div className="mb-4 flex items-end justify-between gap-4">
            <div>
              <h2 id="attention-title" className="text-lg font-extrabold tracking-tight text-slate-900">Agora</h2>
              <p className="muted mt-1 text-sm">Pendências e movimentos que podem exigir ação.</p>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-5">
            {attentionCards.map((card) => (
              <article key={card.label} className="metric-card min-w-0">
                <p className="metric-kicker">{card.label}</p>
                {card.available ? (
                  <>
                    <p className="metric-value">{card.value ?? 0}</p>
                    <p className="mt-2 min-h-9 text-xs leading-5 text-slate-500">{card.description}</p>
                    <Link href={card.href} className="metric-link">Abrir <span aria-hidden="true">→</span></Link>
                  </>
                ) : (
                  <>
                    <p className="mt-3 text-base font-extrabold text-slate-700">Não incluído</p>
                    <p className="mt-2 min-h-9 text-xs leading-5 text-slate-500">Disponível conforme o plano contratado.</p>
                    <Link href="/assinatura" className="metric-link">Ver plano <span aria-hidden="true">→</span></Link>
                  </>
                )}
              </article>
            ))}
          </div>
        </section>

        <section className="mt-8 grid gap-4 lg:grid-cols-[1.35fr_.85fr]">
          <article className="card p-5 sm:p-6">
            <div className="flex flex-col gap-5 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <p className="text-sm font-bold text-slate-500">Desempenho comercial</p>
                <h2 className="mt-1 text-xl font-extrabold tracking-tight">Movimento deste mês</h2>
              </div>
              <Link href="/analytics" className="btn-ghost self-start px-0 sm:px-3">Abrir analytics →</Link>
            </div>
            <div className="mt-6 grid gap-3 sm:grid-cols-3">
              <div className="soft-panel p-4">
                <p className="text-xs font-semibold text-slate-500">Leads neste mês</p>
                <p className="mt-2 text-2xl font-extrabold tracking-tight">{summary.leads_month}</p>
                <p className={`mt-2 text-xs font-bold ${leadDelta >= 0 ? "text-emerald-700" : "text-amber-700"}`}>
                  {leadDelta >= 0 ? "+" : ""}{leadDelta} vs. mês anterior
                </p>
              </div>
              <div className="soft-panel p-4">
                <p className="text-xs font-semibold text-slate-500">Valor potencial aberto</p>
                <p className="mt-2 break-words text-2xl font-extrabold tracking-tight">{formatMoney(summary.potential_value_cents)}</p>
                <p className="mt-2 text-xs leading-5 text-slate-500">Leads ainda em andamento.</p>
              </div>
              <div className="soft-panel p-4">
                <p className="text-xs font-semibold text-slate-500">Total de leads</p>
                <p className="mt-2 text-2xl font-extrabold tracking-tight">{summary.leads_total}</p>
                {crm && summary.customers_total !== null ? (
                  <p className="mt-2 text-xs leading-5 text-slate-500">Clientes convertidos: <strong>{summary.customers_total}</strong></p>
                ) : (
                  <p className="mt-2 text-xs leading-5 text-slate-500">Histórico acumulado da organização.</p>
                )}
              </div>
            </div>
          </article>

          <aside className="card p-5 sm:p-6" aria-labelledby="quick-title">
            <div>
              <p className="text-sm font-bold text-slate-500">Atalhos</p>
              <h2 id="quick-title" className="mt-1 text-xl font-extrabold tracking-tight">Continuar trabalhando</h2>
            </div>
            <div className="mt-5 grid gap-2 sm:grid-cols-2 lg:grid-cols-1">
              {quickActions.map((action) => (
                <Link key={action.href} href={action.href} className="quick-link">
                  <span>
                    <span className="block">{action.label}</span>
                    <span className="mt-0.5 block text-xs font-medium text-slate-500">{action.description}</span>
                  </span>
                  <span className="quick-link-arrow" aria-hidden="true">→</span>
                </Link>
              ))}
            </div>
          </aside>
        </section>
      </main>
    </>
  );
}
