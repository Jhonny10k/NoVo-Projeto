import Link from "next/link";
import { DashboardNav } from "@/components/dashboard/nav";
import { createQuoteAction } from "@/features/quotes/actions";
import { requireUser } from "@/lib/auth/require-user";
import { formatDate, formatMoney } from "@/lib/format";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { hasFeature, requireFeature } from "@/lib/plans/entitlements";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };
type LeadOption = { id: string; name: string };
type CustomerOption = { id: string; name: string };
type ProductOption = { id: string; name: string; price_cents: number | null; promotional_price_cents: number | null };
type ServiceOption = { id: string; name: string; starting_price_cents: number | null };
type QuoteRow = { id: string; status: string; total_cents: number; valid_until: string | null; created_at: string; lead_id: string | null; customer_id: string | null };

const quoteStatus: Record<string, string> = {
  draft: "Rascunho",
  sent: "Enviado",
  viewed: "Visualizado",
  accepted: "Aceito",
  rejected: "Recusado",
  changes_requested: "Alteração solicitada",
  expired: "Expirado"
};

function validUntilLabel(value: string | null) {
  return value ? new Intl.DateTimeFormat("pt-BR", { timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`)) : "Sem validade";
}

export default async function QuotesPage({ searchParams }: Props) {
  await requireFeature("quotes");
  const canExport = await hasFeature("exports");
  await requireUser();
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();
  const params = await searchParams;
  const selectedLead = typeof params.lead === "string" ? params.lead : "";
  const selectedCustomer = typeof params.cliente === "string" ? params.cliente : "";

  const [{ data: leads }, { data: customers }, { data: products }, { data: services }, { data: quotes }] = await Promise.all([
    supabase.from("leads").select("id,name").eq("organization_id", organization.id).order("name"),
    supabase.from("customers").select("id,name").eq("organization_id", organization.id).order("name"),
    supabase.from("products").select("id,name,price_cents,promotional_price_cents").eq("organization_id", organization.id).eq("available", true).order("name"),
    supabase.from("services").select("id,name,starting_price_cents").eq("organization_id", organization.id).eq("active", true).order("name"),
    supabase.from("quotes").select("id,status,total_cents,valid_until,created_at,lead_id,customer_id").eq("organization_id", organization.id).order("created_at", { ascending: false }).limit(100)
  ]);
  const error = typeof params.erro === "string" ? params.erro : "";
  const allQuotes = (quotes ?? []) as QuoteRow[];

  return (
    <>
      <DashboardNav organizationName={organization.name} />
      <main className="container-shell pb-14 pt-7 sm:pt-10">
        <section className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
          <div className="max-w-3xl">
            <p className="eyebrow">Vendas</p>
            <h1 className="page-title mt-4">Orçamentos</h1>
            <p className="muted mt-3 max-w-2xl leading-7">Crie propostas com contexto comercial e acompanhe o que já foi enviado sem misturar cadastro e histórico.</p>
          </div>
          {canExport ? <Link href="/api/export/quotes" className="btn-secondary w-full sm:w-auto">Exportar orçamentos</Link> : <Link href="/assinatura?recurso=exports" className="btn-secondary w-full sm:w-auto">Liberar exportação</Link>}
        </section>

        {error ? <p role="alert" className="mt-5 rounded-xl border border-amber-100 bg-amber-50 p-4 text-sm text-amber-900">Não foi possível criar o orçamento. Revise os dados.</p> : null}

        <section className="mt-7 grid gap-3 sm:grid-cols-3 lg:max-w-2xl">
          <div className="soft-panel p-4"><p className="text-xs font-semibold text-slate-500">Recentes carregados</p><p className="mt-1 text-2xl font-extrabold">{allQuotes.length}</p></div>
          <div className="soft-panel p-4"><p className="text-xs font-semibold text-slate-500">Leads disponíveis</p><p className="mt-1 text-2xl font-extrabold">{(leads ?? []).length}</p></div>
          <div className="soft-panel p-4"><p className="text-xs font-semibold text-slate-500">Clientes disponíveis</p><p className="mt-1 text-2xl font-extrabold">{(customers ?? []).length}</p></div>
        </section>

        <details open={Boolean(selectedLead || selectedCustomer)} className="card mt-6 overflow-hidden">
          <summary className="flex min-h-16 items-center justify-between gap-3 px-5 py-4 sm:px-6">
            <span><span className="block font-extrabold">Criar novo orçamento</span><span className="muted mt-1 block text-xs font-medium">Abra somente quando for montar uma proposta.</span></span>
            <span className="grid h-9 w-9 place-items-center rounded-xl bg-blue-50 font-bold text-blue-700" aria-hidden="true">＋</span>
          </summary>
          <div className="border-t border-slate-100 px-5 pb-6 pt-5 sm:px-6">
            <form action={createQuoteAction} className="grid gap-7">
              <section>
                <div className="mb-4"><p className="text-xs font-extrabold uppercase tracking-[.12em] text-slate-400">1. Para quem</p><h2 className="mt-1 font-extrabold">Vincule a proposta</h2></div>
                <div className="grid gap-4 md:grid-cols-2">
                  <label className="field"><span>Lead</span><select name="lead_id" defaultValue={selectedLead}><option value="">Nenhum</option>{((leads ?? []) as LeadOption[]).map((lead) => <option key={lead.id} value={lead.id}>{lead.name}</option>)}</select></label>
                  <label className="field"><span>Cliente</span><select name="customer_id" defaultValue={selectedCustomer}><option value="">Nenhum</option>{((customers ?? []) as CustomerOption[]).map((customer) => <option key={customer.id} value={customer.id}>{customer.name}</option>)}</select></label>
                </div>
              </section>

              <section>
                <div className="mb-4 flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
                  <div><p className="text-xs font-extrabold uppercase tracking-[.12em] text-slate-400">2. Itens</p><h2 className="mt-1 font-extrabold">O que está sendo proposto</h2></div>
                  <span className="muted text-xs">Até 5 linhas nesta interface.</span>
                </div>
                <div className="grid gap-3">
                  {[0, 1, 2, 3, 4].map((index) => (
                    <div key={index} className="soft-panel p-3 sm:p-4">
                      <div className="mb-3 flex items-center justify-between"><span className="text-xs font-extrabold text-slate-500">Item {index + 1}</span>{index === 0 ? <span className="rounded-full bg-blue-50 px-2 py-1 text-[.65rem] font-bold text-blue-700">Obrigatório</span> : <span className="text-[.68rem] font-medium text-slate-400">Opcional</span>}</div>
                      <div className="grid gap-3 md:grid-cols-[1.25fr_.42fr_.58fr]">
                        <label className="field"><span>Descrição</span><input name="item_description" required={index === 0} list="catalog-items" placeholder={index === 0 ? "Produto ou serviço" : "Adicionar outro item"} /></label>
                        <label className="field"><span>Quantidade</span><input name="item_quantity" inputMode="decimal" defaultValue="1" /></label>
                        <label className="field"><span>Valor unitário (R$)</span><input name="item_unit_price" inputMode="decimal" /></label>
                      </div>
                      <input type="hidden" name="item_type" value="custom" /><input type="hidden" name="item_reference_id" value="" />
                    </div>
                  ))}
                </div>
                <datalist id="catalog-items">
                  {((products ?? []) as ProductOption[]).map((product) => <option key={`p-${product.id}`} value={product.name}>{formatMoney(product.promotional_price_cents ?? product.price_cents)}</option>)}
                  {((services ?? []) as ServiceOption[]).map((service) => <option key={`s-${service.id}`} value={service.name}>{formatMoney(service.starting_price_cents)}</option>)}
                </datalist>
              </section>

              <section>
                <div className="mb-4"><p className="text-xs font-extrabold uppercase tracking-[.12em] text-slate-400">3. Condições</p><h2 className="mt-1 font-extrabold">Ajustes finais</h2></div>
                <div className="grid gap-4 md:grid-cols-3"><label className="field"><span>Desconto (R$)</span><input name="discount" inputMode="decimal" /></label><label className="field"><span>Taxa/acréscimo (R$)</span><input name="fee" inputMode="decimal" /></label><label className="field"><span>Validade</span><input name="valid_until" type="date" /></label></div>
                <label className="field mt-4"><span>Observações</span><textarea name="notes" /></label>
              </section>

              <div className="flex flex-col gap-2 border-t border-slate-100 pt-5 sm:flex-row sm:items-center sm:justify-between">
                <p className="muted text-xs leading-5">O total final continua sendo calculado no banco, dentro da transação.</p>
                <button className="btn-primary w-full sm:w-auto" type="submit">Criar orçamento</button>
              </div>
            </form>
          </div>
        </details>

        <section className="mt-9" aria-labelledby="recent-quotes-title">
          <div className="mb-4"><h2 id="recent-quotes-title" className="text-xl font-extrabold tracking-tight">Orçamentos recentes</h2><p className="muted mt-1 text-sm">Abra uma proposta para publicar, acompanhar resposta ou imprimir.</p></div>
          {allQuotes.length ? (
            <>
              <div className="grid gap-3 md:hidden">
                {allQuotes.map((quote) => (
                  <Link key={quote.id} href={`/orcamentos/${quote.id}`} className="card card-interactive p-4">
                    <div className="flex items-start justify-between gap-3"><div><p className="text-xs font-bold text-slate-500">{formatDate(quote.created_at)}</p><p className="mt-1 text-lg font-extrabold">{formatMoney(quote.total_cents)}</p></div><span className="rounded-full bg-slate-100 px-2.5 py-1 text-[.7rem] font-extrabold text-slate-600">{quoteStatus[quote.status] ?? quote.status}</span></div>
                    <div className="mt-4 flex items-center justify-between gap-3 border-t border-slate-100 pt-3"><span className="text-xs font-medium text-slate-500">Validade: {validUntilLabel(quote.valid_until)}</span><span className="text-sm font-extrabold text-blue-700">Abrir →</span></div>
                  </Link>
                ))}
              </div>
              <div className="card hidden overflow-hidden md:block">
                <div className="overflow-x-auto">
                  <table className="w-full min-w-[760px] text-left">
                    <thead className="bg-slate-50"><tr>{["Criado", "Status", "Total", "Validade", "Ação"].map((heading) => <th className="px-5 py-3.5" key={heading}>{heading}</th>)}</tr></thead>
                    <tbody>{allQuotes.map((quote) => <tr className="border-t border-slate-100" key={quote.id}><td className="px-5 py-4 text-sm">{formatDate(quote.created_at)}</td><td className="px-5 py-4"><span className="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-bold text-slate-600">{quoteStatus[quote.status] ?? quote.status}</span></td><td className="px-5 py-4 font-extrabold">{formatMoney(quote.total_cents)}</td><td className="px-5 py-4 text-sm text-slate-600">{validUntilLabel(quote.valid_until)}</td><td className="px-5 py-4"><Link className="text-sm font-extrabold text-blue-700" href={`/orcamentos/${quote.id}`}>Abrir →</Link></td></tr>)}</tbody>
                  </table>
                </div>
              </div>
            </>
          ) : (
            <div className="card p-7 text-center sm:p-9"><h3 className="font-extrabold">Nenhum orçamento criado</h3><p className="muted mt-2 text-sm">Abra “Criar novo orçamento” para preparar sua primeira proposta.</p></div>
          )}
        </section>
      </main>
    </>
  );
}
