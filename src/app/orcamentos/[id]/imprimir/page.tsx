import Link from "next/link";
import { notFound } from "next/navigation";
import { PrintButton } from "@/components/quotes/print-button";
import { requireUser } from "@/lib/auth/require-user";
import { formatDate, formatMoney } from "@/lib/format";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { requireFeature } from "@/lib/plans/entitlements";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
type Props={params:Promise<{id:string}>};
type Item={id:string;description:string;quantity:number;unit_price_cents:number;total_cents:number};
type Contact={name:string;company?:string|null;whatsapp?:string|null;phone?:string|null;email?:string|null};

export default async function QuotePrintPage({params}:Props){
  await requireFeature("quotes"); await requireUser(); const organization=await requireCurrentOrganization(); const {id}=await params; const supabase=await createClient();
  const [{data:quote},{data:items},{data:company}]=await Promise.all([
    supabase.from("quotes").select("id,status,subtotal_cents,discount_cents,fee_cents,total_cents,notes,valid_until,created_at,lead_id,customer_id").eq("organization_id",organization.id).eq("id",id).maybeSingle(),
    supabase.from("quote_items").select("id,description,quantity,unit_price_cents,total_cents").eq("organization_id",organization.id).eq("quote_id",id).order("created_at"),
    supabase.from("organizations").select("name,logo_url,phone,whatsapp,email,address,city,state,business_hours").eq("id",organization.id).single()
  ]);
  if(!quote) notFound();
  let contact:Contact|null=null;
  if(quote.customer_id){const {data}=await supabase.from("customers").select("name,company,whatsapp,phone,email").eq("organization_id",organization.id).eq("id",quote.customer_id).maybeSingle(); contact=data as Contact|null;}
  else if(quote.lead_id){const {data}=await supabase.from("leads").select("name,company,whatsapp,phone,email").eq("organization_id",organization.id).eq("id",quote.lead_id).maybeSingle(); contact=data as Contact|null;}
  const address=[company?.address,company?.city,company?.state].filter(Boolean).join(" · ");
  return <main className="quote-print container-shell py-8">
    <div className="no-print mb-6 flex flex-wrap gap-2"><Link href={`/orcamentos/${id}`} className="btn-secondary">← Voltar</Link><PrintButton/></div>
    <article className="quote-document bg-white p-8 sm:p-12">
      <header className="flex flex-wrap items-start justify-between gap-6 border-b border-black/10 pb-7"> <div className="flex items-center gap-4">{company?.logo_url?<img src={company.logo_url} alt={`Logo ${company.name}`} className="h-20 w-20 object-contain"/>:null}<div><h1 className="text-2xl font-black">{company?.name??organization.name}</h1>{address?<p className="muted mt-1 text-sm">{address}</p>:null}<p className="muted mt-1 text-sm">{[company?.whatsapp||company?.phone,company?.email].filter(Boolean).join(" · ")}</p></div></div><div className="text-right"><p className="text-xs font-bold uppercase tracking-[.18em] text-blue-700">Orçamento</p><p className="mt-2 text-sm">Emitido em {formatDate(quote.created_at)}</p><p className="mt-1 text-sm">Status: <strong>{quote.status}</strong></p>{quote.valid_until?<p className="mt-1 text-sm">Validade: <strong>{new Intl.DateTimeFormat("pt-BR",{timeZone:"UTC"}).format(new Date(`${quote.valid_until}T00:00:00Z`))}</strong></p>:null}</div></header>
      <section className="mt-7 grid gap-5 sm:grid-cols-2"><div><p className="text-xs font-bold uppercase tracking-wider text-black/50">Cliente</p><p className="mt-2 text-lg font-black">{contact?.name??"Cliente"}</p>{contact?.company?<p className="text-sm">{contact.company}</p>:null}<p className="muted mt-1 text-sm">{[contact?.whatsapp||contact?.phone,contact?.email].filter(Boolean).join(" · ")}</p></div><div className="sm:text-right"><p className="text-xs font-bold uppercase tracking-wider text-black/50">Total</p><p className="mt-2 text-3xl font-black">{formatMoney(quote.total_cents)}</p></div></section>
      <section className="mt-8 overflow-hidden rounded-xl border border-black/10"><table className="w-full border-collapse text-left"><thead><tr className="bg-black/[.03]">{["Descrição","Qtd.","Unitário","Total"].map(h=><th key={h} className="p-3 text-xs uppercase tracking-wide">{h}</th>)}</tr></thead><tbody>{((items??[]) as Item[]).map(item=><tr key={item.id} className="border-t border-black/10"><td className="p-3 text-sm">{item.description}</td><td className="p-3 text-sm">{item.quantity}</td><td className="p-3 text-sm">{formatMoney(item.unit_price_cents)}</td><td className="p-3 text-sm font-bold">{formatMoney(item.total_cents)}</td></tr>)}</tbody></table></section>
      <section className="mt-6 ml-auto grid max-w-sm gap-2 text-sm"><div className="flex justify-between"><span>Subtotal</span><strong>{formatMoney(quote.subtotal_cents)}</strong></div>{quote.discount_cents>0?<div className="flex justify-between"><span>Desconto</span><strong>- {formatMoney(quote.discount_cents)}</strong></div>:null}{quote.fee_cents>0?<div className="flex justify-between"><span>Acréscimo</span><strong>{formatMoney(quote.fee_cents)}</strong></div>:null}<div className="mt-2 flex justify-between border-t border-black/10 pt-3 text-xl"><span>Total</span><strong>{formatMoney(quote.total_cents)}</strong></div></section>
      {quote.notes?<section className="mt-8 border-t border-black/10 pt-6"><h2 className="font-black">Observações</h2><p className="mt-2 whitespace-pre-wrap text-sm">{quote.notes}</p></section>:null}
      <footer className="mt-10 border-t border-black/10 pt-5 text-xs text-black/50"><p>Documento gerado pelo sistema da empresa. Para uma cópia em PDF, utilize “Imprimir / Salvar PDF”.</p></footer>
    </article>
  </main>;
}
