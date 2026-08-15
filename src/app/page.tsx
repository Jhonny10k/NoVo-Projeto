import Link from "next/link";
import { MarketingHeader } from "@/components/marketing/header";
import { MarketingFooter } from "@/components/marketing/footer";

const benefits = [
  ["Seu site profissional", "Presença digital moderna, rápida e preparada para SEO."],
  ["Orçamentos organizados", "Receba solicitações e acompanhe cada oportunidade sem planilhas soltas."],
  ["CRM integrado", "Centralize leads, clientes, histórico e próximos contatos."],
  ["Operação em um só lugar", "Produtos, serviços, tarefas e indicadores conectados à mesma empresa."]
] as const;

export default function HomePage() {
  return (
    <>
      <MarketingHeader />
      <main>
        <section className="container-shell grid gap-10 py-20 lg:grid-cols-[1.1fr_.9fr] lg:items-center">
          <div>
            <p className="mb-3 text-sm font-bold uppercase tracking-[.18em] text-blue-700">Seu negócio digital completo</p>
            <h1 className="max-w-3xl text-4xl font-black leading-tight tracking-tight sm:text-6xl">
              Transforme seu negócio em uma operação digital completa.
            </h1>
            <p className="muted mt-6 max-w-2xl text-lg leading-8">
              Site, clientes, orçamentos e organização comercial trabalhando juntos para sua empresa vender com mais clareza.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <Link href="/cadastro" className="btn-primary">Começar agora</Link>
              <Link href="/demo" className="btn-secondary">Ver demonstração</Link>
            </div>
          </div>

          <div className="card p-6 sm:p-8" aria-label="Resumo do produto">
            <p className="text-sm font-bold text-blue-700">VISÃO DA OPERAÇÃO</p>
            <div className="mt-5 grid gap-3">
              {["Novo lead", "Orçamento enviado", "Cliente respondeu", "Tarefa de retorno"].map((item, index) => (
                <div key={item} className="flex items-center justify-between rounded-xl border border-black/5 p-4">
                  <span className="font-semibold">{item}</span>
                  <span className="text-sm muted">Etapa {index + 1}</span>
                </div>
              ))}
            </div>
            <p className="muted mt-4 text-xs">
              Exemplo visual do fluxo. Nenhuma métrica financeira é simulada nesta seção.
            </p>
          </div>
        </section>

        <section className="border-y border-black/5 bg-white py-16">
          <div className="container-shell">
            <h2 className="text-3xl font-black tracking-tight">Feito para organizar e vender melhor</h2>
            <div className="mt-8 grid gap-4 md:grid-cols-2">
              {benefits.map(([title, description]) => (
                <article key={title} className="card p-6">
                  <h3 className="text-lg font-bold">{title}</h3>
                  <p className="muted mt-2 leading-7">{description}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="container-shell py-16">
          <div className="card p-8 sm:p-10">
            <h2 className="text-3xl font-black tracking-tight">Sua empresa merece mais do que apenas um site.</h2>
            <p className="muted mt-3 max-w-2xl text-lg">Centralize clientes, orçamentos e atendimento em um único lugar.</p>
            <Link href="/cadastro" className="btn-primary mt-6">Criar minha conta</Link>
          </div>
        </section>
      </main>
      <MarketingFooter />
    </>
  );
}
