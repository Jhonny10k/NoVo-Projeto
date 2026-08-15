import Link from "next/link";
import { notFound } from "next/navigation";
import { DashboardNav } from "@/components/dashboard/nav";
import { EventTimeline } from "@/components/timeline/event-timeline";
import { requireUser } from "@/lib/auth/require-user";
import { formatDate, formatMoney } from "@/lib/format";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { requireFeature } from "@/lib/plans/entitlements";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
type Props = { params: Promise<{ id: string }> };
type Event = { id: string; event_type: string; metadata: Record<string, unknown> | null; created_at: string };
type Quote = { id: string; status: string; total_cents: number; created_at: string };

export default async function CustomerDetailPage({params }: Props) {
  await requireFeature("crm");
  await requireUser();
  const organization = await requireCurrentOrganization();
  const { id } = await params;
  const supabase = await createClient();
  const { data: customer } = await supabase.from("customers").select("id,name,phone,whatsapp,email,company,notes,source_lead_id,created_at").eq("organization_id", organization.id).eq("id", id).maybeSingle();
  if (!customer) notFound();

  const queries = [
    supabase.from("events").select("id,event_type,metadata,created_at").eq("organization_id", organization.id).eq("entity_type", "customer").eq("entity_id", id).order("created_at", { ascending: false }).limit(200),
    supabase.from("quotes").select("id,status,total_cents,created_at").eq("organization_id", organization.id).eq("customer_id", id).order("created_at", { ascending: false }).limit(50)
  ] as const;
  const [{ data: customerEvents }, { data: quotes }] = await Promise.all(queries);
  let leadEvents: Event[] = [];
  if (customer.source_lead_id) {
    const { data } = await supabase.from("events").select("id,event_type,metadata,created_at").eq("organization_id", organization.id).eq("entity_type", "lead").eq("entity_id", customer.source_lead_id).order("created_at", { ascending: false }).limit(200);
    leadEvents = (data ?? []) as Event[];
  }
  const events = ([...((customerEvents ?? []) as Event[]), ...leadEvents]).sort((a,b) => Date.parse(b.created_at) - Date.parse(a.created_at));

  return <><DashboardNav organizationName={organization.name} /><main className="container-shell py-10">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-bold uppercase tracking-widest text-blue-700">Cliente</p><h1 className="mt-1 text-3xl font-black">{customer.name}</h1><p className="muted mt-2">Histórico consolidado desde o lead de origem.</p></div><div className="flex gap-2"><Link href="/clientes" className="btn-secondary">Voltar</Link><Link href={`/orcamentos?cliente=${customer.id}`} className="btn-primary">Novo orçamento</Link></div></div>
    <section className="mt-7 grid gap-5 lg:grid-cols-[0.85fr_1.15fr]"><div className="grid content-start gap-5"><article className="card p-5"><h2 className="font-black">Dados</h2><dl className="mt-4 grid gap-2 text-sm"><div><dt className="muted">Contato</dt><dd>{customer.whatsapp || customer.phone || customer.email || "—"}</dd></div><div><dt className="muted">Empresa</dt><dd>{customer.company || "—"}</dd></div><div><dt className="muted">Cliente desde</dt><dd>{formatDate(customer.created_at)}</dd></div></dl>{customer.notes ? <div className="mt-4"><p className="muted text-xs">Observações</p><p className="mt-1 whitespace-pre-wrap text-sm">{customer.notes}</p></div> : null}</article><article className="card p-5"><h2 className="font-black">Orçamentos</h2><div className="mt-3 grid gap-2">{((quotes ?? []) as Quote[]).map((quote) => <Link key={quote.id} href={`/orcamentos/${quote.id}`} className="rounded-xl border border-black/5 p-3 text-sm"><span className="font-semibold">{formatMoney(quote.total_cents)}</span><span className="muted ml-2">{quote.status} · {formatDate(quote.created_at)}</span></Link>)}{(quotes ?? []).length === 0 ? <p className="muted text-sm">Nenhum orçamento.</p> : null}</div></article></div><article className="card p-5"><h2 className="font-black">Linha do tempo</h2><div className="mt-4"><EventTimeline events={events} /></div></article></section>
  </main></>;
}
