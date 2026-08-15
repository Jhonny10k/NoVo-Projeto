import { notFound } from "next/navigation";
import { respondPublicQuoteAction } from "@/features/quotes/actions";
import { formatMoney } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
type Props = { params: Promise<{ token: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> };
type PublicQuote = { quote: { status: string; subtotal_cents: number; discount_cents: number; fee_cents: number; total_cents: number; notes: string | null; valid_until: string | null; created_at: string }; organization: { name: string; phone: string | null; whatsapp: string | null; email: string | null; city: string | null; state: string | null }; customer: { name: string; whatsapp: string | null; email: string | null }; items: Array<{ id: string; description: string; quantity: number; unit_price_cents: number; total_cents: number }> };

export default async function PublicQuotePage({ params, searchParams }: Props) {
  const { token } = await params;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_public_quote", { p_token: token });
  if (error || !data) notFound();
  const content = data as PublicQuote;
  const query = await searchParams;
  const feedback = typeof query.status === "string" ? query.status : "";
  const errorMessage = typeof query.erro === "string" ? query.erro : "";
  const canRespond = ["sent", "viewed", "change_requested"].includes(content.quote.status);
  const approve = respondPublicQuoteAction.bind(null, token, "approved");
  const reject = respondPublicQuoteAction.bind(null, token, "rejected");
  const change = respondPublicQuoteAction.bind(null, token, "change_requested");

  return <main className="container-shell py-10 sm:py-16">
    <section className="card mx-auto max-w-4xl overflow-hidden"><header className="border-b border-black/5 p-6 sm:p-8"><p className="text-sm font-bold uppercase tracking-widest text-blue-700">Orçamento</p><h1 className="mt-2 text-3xl font-black">{content.organization.name}</h1><p className="muted mt-2">Preparado para {content.customer.name}</p></header>
      {feedback ? <div className="m-6 rounded-xl bg-emerald-50 p-4 text-sm font-semibold">Resposta registrada com sucesso.</div> : null}{errorMessage ? <div role="alert" className="m-6 rounded-xl bg-amber-50 p-4 text-sm">{errorMessage === "limite" ? "Muitas tentativas de resposta. Tente novamente mais tarde." : "Não foi possível registrar a resposta agora."}</div> : null}
      <div className="overflow-x-auto"><table className="w-full min-w-[620px]"><thead><tr className="border-b border-black/5 text-left">{["Item","Qtd.","Unitário","Total"].map((h) => <th className="p-4" key={h}>{h}</th>)}</tr></thead><tbody>{content.items.map((item) => <tr className="border-b border-black/5 last:border-0" key={item.id}><td className="p-4">{item.description}</td><td className="p-4">{item.quantity}</td><td className="p-4">{formatMoney(item.unit_price_cents)}</td><td className="p-4 font-semibold">{formatMoney(item.total_cents)}</td></tr>)}</tbody></table></div>
      <div className="border-t border-black/5 p-6 sm:p-8"><div className="ml-auto grid max-w-sm gap-2 text-sm"><div className="flex justify-between"><span>Subtotal</span><strong>{formatMoney(content.quote.subtotal_cents)}</strong></div>{content.quote.discount_cents ? <div className="flex justify-between"><span>Desconto</span><strong>- {formatMoney(content.quote.discount_cents)}</strong></div> : null}{content.quote.fee_cents ? <div className="flex justify-between"><span>Acréscimo</span><strong>{formatMoney(content.quote.fee_cents)}</strong></div> : null}<div className="mt-2 flex justify-between text-xl"><span>Total</span><strong>{formatMoney(content.quote.total_cents)}</strong></div></div>
        {content.quote.notes ? <div className="mt-6"><h2 className="font-bold">Observações</h2><p className="muted mt-2 whitespace-pre-wrap">{content.quote.notes}</p></div> : null}
        <div className="mt-6 text-sm"><strong>Status:</strong> {content.quote.status}{content.quote.valid_until ? <> · <strong>Validade:</strong> {new Intl.DateTimeFormat("pt-BR", { timeZone: "UTC" }).format(new Date(`${content.quote.valid_until}T00:00:00Z`))}</> : null}</div>
        {canRespond ? <div className="mt-7 grid gap-3 sm:grid-cols-3"><form action={approve}><button className="btn-primary w-full" type="submit">Aceitar orçamento</button></form><form action={change}><button className="btn-secondary w-full" type="submit">Solicitar alteração</button></form><form action={reject}><button className="btn-danger w-full" type="submit">Recusar</button></form></div> : <p className="mt-7 rounded-xl bg-black/5 p-4 text-sm font-semibold">Este orçamento já recebeu uma resposta ou não está mais disponível para alteração.</p>}
      </div>
    </section>
  </main>;
}
