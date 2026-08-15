import Link from "next/link";
import { MarketingHeader } from "@/components/marketing/header";
import { MarketingFooter } from "@/components/marketing/footer";

const features = [
  ["01", "CRM e atendimento", "Leads, clientes, histórico e conversas organizados para sua equipe saber quem precisa de atenção."],
  ["02", "Orçamentos e catálogo", "Produtos, serviços e propostas conectados ao mesmo fluxo comercial, sem planilhas espalhadas."],
  ["03", "Agenda e tarefas", "Compromissos, retornos e pendências no mesmo ambiente para reduzir esquecimentos na operação."],
  ["04", "Site e crescimento", "Presença digital, analytics, automações e recursos de IA integrados à rotina da empresa."]
] as const;

const operationFlow = [
  ["Lead recebido", "Novo contato"],
  ["Orçamento enviado", "Em negociação"],
  ["Retorno agendado", "Próxima ação"],
  ["Atendimento centralizado", "Histórico salvo"]
] as const;

export default function HomePage() {
  return (
    <>
      <MarketingHeader />
      <main>
        <section className="marketing-hero">
          <div className="container-shell grid gap-12 lg:grid-cols-[1.08fr_.92fr] lg:items-center lg:gap-16">
            <div>
              <p className="eyebrow">Gestão comercial para PMEs</p>
              <h1 className="hero-title mt-5">Sua operação comercial inteira, finalmente no mesmo lugar.</h1>
              <p className="hero-description mt-6">
                Centralize site, CRM, atendimento, orçamentos, agenda e tarefas em uma experiência única para sua empresa vender e se organizar melhor.
              </p>
              <div className="mt-8 flex flex-col gap-3 sm:flex-row">
                <Link href="/cadastro" className="btn-primary w-full sm:w-auto">Começar agora</Link>
                <Link href="/demo" className="btn-secondary w-full sm:w-auto">Ver demonstração</Link>
              </div>
              <div className="mt-7 flex flex-wrap gap-2" aria-label="Principais recursos">
                {["CRM", "Orçamentos", "Agenda", "Atendimento"].map((item) => (
                  <span key={item} className="rounded-full border border-slate-200 bg-white px-3 py-1.5 text-xs font-bold text-slate-600 shadow-sm">
                    {item}
                  </span>
                ))}
              </div>
            </div>

            <div className="product-preview" aria-label="Prévia do fluxo operacional">
              <div className="preview-topbar">
                <span className="preview-dot" /><span className="preview-dot" /><span className="preview-dot" />
                <span className="ml-2 text-[.68rem] font-semibold uppercase tracking-[.14em] text-slate-500">Visão da operação</span>
              </div>
              <div className="preview-body">
                <div className="mb-5 flex items-end justify-between gap-4">
                  <div>
                    <p className="text-xs font-semibold text-slate-400">Fluxo comercial</p>
                    <p className="mt-1 text-xl font-extrabold tracking-tight text-white">O próximo passo fica claro.</p>
                  </div>
                  <span className="rounded-full border border-blue-400/20 bg-blue-400/10 px-2.5 py-1 text-[.66rem] font-bold text-blue-200">Organizado</span>
                </div>
                <div className="grid gap-2.5">
                  {operationFlow.map(([label, status]) => (
                    <div key={label} className="preview-row">
                      <span className="min-w-0 truncate text-sm font-semibold text-slate-200">{label}</span>
                      <span className="preview-status shrink-0">{status}</span>
                    </div>
                  ))}
                </div>
                <p className="mt-4 text-xs leading-5 text-slate-500">Prévia ilustrativa do fluxo de trabalho, sem métricas comerciais simuladas.</p>
              </div>
            </div>
          </div>
        </section>

        <section className="border-y border-slate-200/80 bg-white py-16 sm:py-20">
          <div className="container-shell">
            <div className="max-w-2xl">
              <p className="eyebrow">Uma operação conectada</p>
              <h2 className="mt-4 text-3xl font-extrabold tracking-[-.035em] text-slate-950 sm:text-4xl">Menos módulos soltos. Mais continuidade no trabalho.</h2>
              <p className="muted mt-4 leading-7">Cada área existe para apoiar o mesmo processo comercial, da entrada do lead ao relacionamento com o cliente.</p>
            </div>
            <div className="mt-9 grid gap-4 md:grid-cols-2">
              {features.map(([number, title, description]) => (
                <article key={title} className="feature-tile">
                  <div className="feature-number">{number}</div>
                  <h3 className="mt-5 text-lg font-extrabold tracking-tight text-slate-900">{title}</h3>
                  <p className="muted mt-2 max-w-xl text-sm leading-6 sm:text-base sm:leading-7">{description}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="container-shell py-16 sm:py-20">
          <div className="grid gap-5 lg:grid-cols-[.82fr_1.18fr]">
            <article className="card p-6 sm:p-8">
              <p className="eyebrow">Comece pelo essencial</p>
              <h2 className="mt-4 text-2xl font-extrabold tracking-tight sm:text-3xl">Organize a rotina sem trocar de ferramenta a cada etapa.</h2>
              <p className="muted mt-4 leading-7">O painel reúne as ações do dia, enquanto cada módulo aprofunda somente o que você precisa naquele momento.</p>
              <Link href="/planos" className="btn-secondary mt-6">Conhecer os planos</Link>
            </article>
            <article className="overflow-hidden rounded-[20px] border border-blue-200 bg-gradient-to-br from-blue-600 to-indigo-700 p-7 text-white shadow-[0_24px_60px_rgba(37,99,235,.22)] sm:p-10">
              <p className="text-xs font-extrabold uppercase tracking-[.14em] text-blue-100">Pronto para estruturar a operação?</p>
              <h2 className="mt-4 max-w-2xl text-3xl font-extrabold tracking-[-.04em] sm:text-4xl">Sua empresa merece uma experiência de gestão tão organizada quanto o serviço que entrega.</h2>
              <p className="mt-4 max-w-2xl text-sm leading-7 text-blue-100 sm:text-base">Crie sua conta, configure a empresa e avance a partir de um painel pensado para priorizar o trabalho — não para exibir uma lista infinita de funções.</p>
              <Link href="/cadastro" className="mt-7 inline-flex min-h-11 items-center justify-center rounded-xl bg-white px-5 text-sm font-extrabold text-blue-700 shadow-sm transition hover:bg-blue-50">Criar minha conta</Link>
            </article>
          </div>
        </section>
      </main>
      <MarketingFooter />
    </>
  );
}
