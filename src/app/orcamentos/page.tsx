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

export default async function QuotesPage({searchParams }: Props) {
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

  return <>
    <DashboardNav organizationName={organization.name} />
    <main className="container-shell py-10">
      <div><p className="text-sm font-bold uppercase tracking-widest text-blue-700">Orçamentos</p><h1 className="mt-1 text-3xl font-black">Criar e acompanhar propostas</h1><div className="mt-4">{canExport ? <Link href="/api/export/quotes" className="btn-secondary">Exportar orçamentos</Link> : <Link href="/assinatura?recurso=exports" className="btn-secondary">Liberar exportação</Link>}</div><p className="muted mt-2">O total é calculado no banco em uma transação, item por item.</p></div>
      {error ? <p role="alert" className="mt-5 rounded-xl bg-amber-50 p-4 text-sm">Não foi possível criar o orçamento. Revise os dados.</p> : null}

      <details open={Boolean(selectedLead || selectedCustomer)} className="card mt-7 p-5">
        <summary className="cursor-pointer font-black">+ Novo orçamento</summary>
        <form action={createQuoteAction} className="mt-5 grid gap-5">
          <div className="grid gap-4 md:grid-cols-2">
            <label className="field"><span>Lead</span><select name="lead_id" defaultValue={selectedLead}><option value="">Nenhum</option>{((leads ?? []) as LeadOption[]).map((lead) => <option key={lead.id} value={lead.id}>{lead.name}</option>)}</select></label>
            <label className="field"><span>Cliente</span><select name="customer_id" defaultValue={selectedCustomer}><option value="">Nenhum</option>{((customers ?? []) as CustomerOption[]).map((customer) => <option key={customer.id} value={customer.id}>{customer.name}</option>)}</select></label>
          </div>
          <div>
            <div className="flex items-center justify-between gap-4"><h2 className="font-black">Itens</h2><span className="muted text-xs">Adicione até 5 linhas nesta primeira interface.</span></div>
            <div className="mt-3 grid gap-3">
              {[0,1,2,3,4].map((index) => <div key={index} className="grid gap-3 rounded-xl border border-black/5 p-3 md:grid-cols-[1.2fr_.45fr_.55fr]">
                <label className="field"><span>Descrição {index === 0 ? "*" : ""}</span><input name="item_description" required={index === 0} list="catalog-items" /></label>
                <label className="field"><span>Qtd.</span><input name="item_quantity" inputMode="decimal" defaultValue="1" /></label>
                <label className="field"><span>Valor unitário (R$)</span><input name="item_unit_price" inputMode="decimal" /></label>
                <input type="hidden" name="item_type" value="custom" /><input type="hidden" name="item_reference_id" value="" />
              </div>)}
            </div>
            <datalist id="catalog-items">{((products ?? []) as ProductOption[]).map((p) => <option key={`p-${p.id}`} value={p.name}>{formatMoney(p.promotional_price_cents ?? p.price_cents)}</option>)}{((services ?? []) as ServiceOption[]).map((s) => <option key={`s-${s.id}`} value={s.name}>{formatMoney(s.starting_price_cents)}</option>)}</datalist>
          </div>
          <div className="grid gap-4 md:grid-cols-3"><label className="field"><span>Desconto (R$)</span><input name="discount" inputMode="decimal" /></label><label className="field"><span>Taxa/acréscimo (R$)</span><input name="fee" inputMode="decimal" /></label><label className="field"><span>Validade</span><input name="valid_until" type="date" /></label></div>
          <label className="field"><span>Observações</span><textarea name="notes" /></label>
          <button className="btn-primary md:w-fit" type="submit">Criar orçamento</button>
        </form>
      </details>

      <section className="mt-9"><h2 className="text-xl font-black">Orçamentos recentes</h2>{quotes && quotes.length ? <div className="card mt-4 overflow-x-auto"><table className="w-full min-w-[760px] border-collapse text-left"><thead><tr className="border-b border-black/5">{["Criado","Status","Total","Validade","Ação"].map((h) => <th className="p-4 text-sm font-bold" key={h}>{h}</th>)}</tr></thead><tbody>{(quotes as QuoteRow[]).map((quote) => <tr className="border-b border-black/5 last:border-0" key={quote.id}><td className="p-4 text-sm">{formatDate(quote.created_at)}</td><td className="p-4 text-sm font-semibold">{quote.status}</td><td className="p-4 font-semibold">{formatMoney(quote.total_cents)}</td><td className="p-4 text-sm">{quote.valid_until ? new Intl.DateTimeFormat("pt-BR", { timeZone: "UTC" }).format(new Date(`${quote.valid_until}T00:00:00Z`)) : "—"}</td><td className="p-4"><Link className="text-sm font-bold text-blue-700" href={`/orcamentos/${quote.id}`}>Abrir</Link></td></tr>)}</tbody></table></div> : <div className="card mt-4 p-6"><p className="font-semibold">Nenhum orçamento criado.</p></div>}</section>
    </main>
  </>;
}
