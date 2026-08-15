import Link from "next/link";
import { DashboardNav } from "@/components/dashboard/nav";
import { requireUser } from "@/lib/auth/require-user";
import { formatDate } from "@/lib/format";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { hasFeature, requireFeature } from "@/lib/plans/entitlements";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };
type Customer = { id: string; name: string; phone: string | null; whatsapp: string | null; email: string | null; company: string | null; created_at: string; source_lead_id: string | null };

export default async function CustomersPage({searchParams }: Props) {
  await requireFeature("crm");
  const canExport = await hasFeature("exports");
  await requireUser();
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();
  const { data: customers, error } = await supabase.from("customers").select("id,name,phone,whatsapp,email,company,created_at,source_lead_id").eq("organization_id", organization.id).order("created_at", { ascending: false }).limit(300);
  const params = await searchParams;
  const converted = params.status === "convertido";

  return <>
    <DashboardNav organizationName={organization.name} />
    <main className="container-shell py-10">
      <div className="flex flex-wrap items-end justify-between gap-4"><div><h1 className="text-3xl font-black">Clientes</h1><div className="mt-4">{canExport ? <Link href="/api/export/customers" className="btn-secondary">Exportar clientes</Link> : <Link href="/assinatura?recurso=exports" className="btn-secondary">Liberar exportação</Link>}</div><p className="muted mt-2">Clientes convertidos a partir do CRM.</p></div><Link href="/crm" className="btn-secondary">Voltar ao CRM</Link></div>
      {converted ? <p className="mt-5 rounded-xl bg-emerald-50 p-4 text-sm font-semibold">Lead convertido em cliente.</p> : null}
      {error ? <div className="card mt-6 p-5">Não foi possível carregar os clientes.</div> : customers && customers.length ? <div className="card mt-6 overflow-x-auto"><table className="w-full min-w-[760px] border-collapse text-left"><thead><tr className="border-b border-black/5">{["Cliente","Contato","Empresa","Desde","Ações"].map((h) => <th key={h} className="p-4 text-sm font-bold">{h}</th>)}</tr></thead><tbody>{(customers as Customer[]).map((customer) => <tr key={customer.id} className="border-b border-black/5 last:border-0"><td className="p-4 font-semibold"><Link href={`/clientes/${customer.id}`} className="hover:text-blue-700">{customer.name}</Link></td><td className="p-4 text-sm">{customer.whatsapp || customer.phone || customer.email || "—"}</td><td className="p-4 text-sm">{customer.company || "—"}</td><td className="p-4 text-sm">{formatDate(customer.created_at)}</td><td className="p-4"><div className="flex gap-3"><Link className="text-sm font-bold text-blue-700" href={`/clientes/${customer.id}`}>Histórico</Link><Link className="text-sm font-bold text-blue-700" href={`/orcamentos?cliente=${customer.id}`}>Novo orçamento</Link></div></td></tr>)}</tbody></table></div> : <div className="card mt-6 p-6"><h2 className="font-bold">Nenhum cliente ainda.</h2><p className="muted mt-2">Quando um lead for fechado no CRM, converta-o em cliente.</p></div>}
    </main>
  </>;
}
