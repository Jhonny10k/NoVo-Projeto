import Link from "next/link";
import { notFound } from "next/navigation";
import { DashboardNav } from "@/components/dashboard/nav";
import { publishQuoteAction } from "@/features/quotes/actions";
import { sendQuoteEmailAction } from "@/features/communications/actions";
import { requireUser } from "@/lib/auth/require-user";
import { formatDate, formatMoney } from "@/lib/format";
import { getPublicAppUrl } from "@/lib/env";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { hasFeature, requireFeature } from "@/lib/plans/entitlements";
import { isTransactionalEmailConfigured } from "@/lib/communications/email";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
type Props = { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> };
type QuoteItem = { id: string; description: string; quantity: number; unit_price_cents: number; total_cents: number };

export default async function QuoteDetailsPage({params, searchParams }: Props) {
  await requireFeature("quotes");
  await requireUser();
  const organization = await requireCurrentOrganization();
  const canEmail = await hasFeature("email_transactional");
  const { id } = await params;
  const supabase = await createClient();
  const [{ data: quote }, { data: items }] = await Promise.all([
    supabase.from("quotes").select("id,status,public_token,subtotal_cents,discount_cents,fee_cents,total_cents,notes,valid_until,created_at,lead_id,customer_id").eq("organization_id", organization.id).eq("id", id).maybeSingle(),
    supabase.from("quote_items").select("id,description,quantity,unit_price_cents,total_cents").eq("organization_id", organization.id).eq("quote_id", id).order("created_at")
  ]);
  if (!quote) notFound();
  const query = await searchParams;
  const status = typeof query.status === "string" ? query.status : "";
  const error = typeof query.erro === "string" ? query.erro : "";
  const publicEnabled = quote.status !== "draft";
  const publicUrl = `${getPublicAppUrl()}/orcamento/${quote.public_token}`;

  return <><DashboardNav organizationName={organization.name} /><main className="container-shell py-10">
    <Link href="/orcamentos" className="text-sm font-bold text-blue-700">← Orçamentos</Link>
    <div className="mt-4 flex flex-wrap items-start justify-between gap-4"><div><h1 className="text-3xl font-black">Orçamento</h1><p className="muted mt-2">Criado em {formatDate(quote.created_at)} · Status: <strong>{quote.status}</strong></p></div><div className="flex flex-wrap gap-2"><Link href={`/orcamentos/${quote.id}/imprimir`} className="btn-secondary">Imprimir / PDF</Link>{publicEnabled ? <Link href={`/orcamento/${quote.public_token}`} className="btn-secondary">Visualizar como cliente</Link> : null}</div></div>
    {status === "publicado" ? <p className="mt-5 rounded-xl bg-emerald-50 p-4 text-sm font-semibold">Link público liberado.</p> : null}{status === "email_enviado" ? <p className="mt-5 rounded-xl bg-emerald-50 p-4 text-sm font-semibold">Orçamento enviado por e-mail pelo provider configurado.</p> : null}{error ? <p className="mt-5 rounded-xl bg-amber-50 p-4 text-sm">Não foi possível concluir: {error.replaceAll("_"," ")}.</p> : null}
    <section className="card mt-7 overflow-hidden"><div className="border-b border-black/5 p-6"><h2 className="font-black">Itens</h2></div><div className="overflow-x-auto"><table className="w-full min-w-[680px]"><thead><tr className="border-b border-black/5 text-left">{["Descrição","Qtd.","Unitário","Total"].map((h) => <th className="p-4 text-sm" key={h}>{h}</th>)}</tr></thead><tbody>{((items ?? []) as QuoteItem[]).map((item) => <tr className="border-b border-black/5 last:border-0" key={item.id}><td className="p-4">{item.description}</td><td className="p-4">{item.quantity}</td><td className="p-4">{formatMoney(item.unit_price_cents)}</td><td className="p-4 font-semibold">{formatMoney(item.total_cents)}</td></tr>)}</tbody></table></div><div className="grid gap-2 border-t border-black/5 p-6 text-sm sm:ml-auto sm:max-w-sm"><div className="flex justify-between"><span>Subtotal</span><strong>{formatMoney(quote.subtotal_cents)}</strong></div><div className="flex justify-between"><span>Desconto</span><strong>- {formatMoney(quote.discount_cents)}</strong></div><div className="flex justify-between"><span>Acréscimo</span><strong>{formatMoney(quote.fee_cents)}</strong></div><div className="mt-2 flex justify-between text-lg"><span>Total</span><strong>{formatMoney(quote.total_cents)}</strong></div></div></section>
    {quote.notes ? <section className="card mt-5 p-5"><h2 className="font-bold">Observações</h2><p className="muted mt-2 whitespace-pre-wrap">{quote.notes}</p></section> : null}
    <section className="card mt-5 p-5"><h2 className="font-black">Compartilhamento</h2>{publicEnabled ? <><p className="muted mt-2 text-sm">Copie este endereço para enviar ao cliente:</p><code className="mt-3 block overflow-x-auto rounded-lg bg-black/5 p-3 text-sm">{publicUrl}</code></> : <form action={publishQuoteAction} className="mt-4"><input type="hidden" name="quote_id" value={quote.id} /><button className="btn-primary" type="submit">Liberar link para o cliente</button><p className="muted mt-2 text-xs">Esta ação não envia mensagem automaticamente; apenas disponibiliza o link público.</p></form>}</section>
    <section className="card mt-5 p-5"><h2 className="font-black">Enviar por e-mail</h2>{canEmail&&isTransactionalEmailConfigured()?<form action={sendQuoteEmailAction} className="mt-4"><input type="hidden" name="quote_id" value={quote.id}/><button className="btn-primary" type="submit">Liberar link e enviar e-mail</button><p className="muted mt-2 text-xs">O destinatário é o e-mail real do lead/cliente. Se o orçamento ainda estiver em rascunho, o link é liberado antes do envio.</p></form>:<p className="muted mt-3 text-sm">O e-mail transacional não está disponível no plano ou o provider ainda não foi configurado. <Link href="/integracoes" className="font-bold underline">Ver integrações</Link>.</p>}</section>
  </main></>;
}
