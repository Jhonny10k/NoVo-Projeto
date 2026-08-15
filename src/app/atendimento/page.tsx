import Link from "next/link";
import { DashboardNav } from "@/components/dashboard/nav";
import { requireUser } from "@/lib/auth/require-user";
import { formatDate } from "@/lib/format";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { hasFeature } from "@/lib/plans/entitlements";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };
type Message = { id: string; channel: "email" | "whatsapp"; direction: "inbound" | "outbound"; provider: string; lead_id: string | null; customer_id: string | null; sender: string | null; recipient: string | null; subject: string | null; body: string | null; template_name: string | null; status: string; created_at: string };
type NamedEntity = { id: string; name: string };

const statusLabels: Record<string, string> = {
  queued: "Na fila",
  pending: "Pendente",
  sent: "Aceita pelo canal",
  delivered: "Entregue",
  read: "Lida",
  failed: "Falhou",
  received: "Recebida"
};

export default async function AtendimentoPage({ searchParams }: Props) {
  await requireUser();
  const organization = await requireCurrentOrganization();
  const params = await searchParams;
  const channel = typeof params.canal === "string" && ["email", "whatsapp"].includes(params.canal) ? params.canal : "";
  const direction = typeof params.direcao === "string" && ["inbound", "outbound"].includes(params.direcao) ? params.direcao : "";
  const [emailAllowed, whatsappAllowed] = await Promise.all([hasFeature("email_transactional"), hasFeature("whatsapp_official")]);
  const supabase = await createClient();

  let query = supabase
    .from("communication_messages")
    .select("id,channel,direction,provider,lead_id,customer_id,sender,recipient,subject,body,template_name,status,created_at")
    .eq("organization_id", organization.id)
    .order("created_at", { ascending: false })
    .limit(200);
  if (channel) query = query.eq("channel", channel);
  if (direction) query = query.eq("direction", direction);

  const { data } = await query;
  const messages = (data ?? []) as Message[];
  const leadIds = [...new Set(messages.map((message) => message.lead_id).filter(Boolean))] as string[];
  const customerIds = [...new Set(messages.map((message) => message.customer_id).filter(Boolean))] as string[];
  const [{ data: leads }, { data: customers }] = await Promise.all([
    leadIds.length ? supabase.from("leads").select("id,name").eq("organization_id", organization.id).in("id", leadIds) : Promise.resolve({ data: [] }),
    customerIds.length ? supabase.from("customers").select("id,name").eq("organization_id", organization.id).in("id", customerIds) : Promise.resolve({ data: [] })
  ]);
  const leadNames = new Map(((leads ?? []) as NamedEntity[]).map((item) => [item.id, item.name]));
  const customerNames = new Map(((customers ?? []) as NamedEntity[]).map((item) => [item.id, item.name]));
  const inboundCount = messages.filter((message) => message.direction === "inbound").length;
  const outboundCount = messages.length - inboundCount;

  return (
    <>
      <DashboardNav organizationName={organization.name} />
      <main className="container-shell pb-14 pt-7 sm:pt-10">
        <section className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
          <div className="max-w-3xl">
            <p className="eyebrow">Relacionamento</p>
            <h1 className="page-title mt-4">Atendimento</h1>
            <p className="muted mt-3 max-w-2xl leading-7">Veja o histórico dos canais conectados sem misturar mensagens com configurações técnicas.</p>
          </div>
          <Link href="/integracoes" className="btn-secondary w-full sm:w-auto">Configurar canais</Link>
        </section>

        <section className="mt-7 grid grid-cols-3 gap-3 sm:max-w-xl">
          <div className="soft-panel p-4"><p className="text-xs font-semibold text-slate-500">Exibidas</p><p className="mt-1 text-2xl font-extrabold">{messages.length}</p></div>
          <div className="soft-panel p-4"><p className="text-xs font-semibold text-slate-500">Recebidas</p><p className="mt-1 text-2xl font-extrabold">{inboundCount}</p></div>
          <div className="soft-panel p-4"><p className="text-xs font-semibold text-slate-500">Enviadas</p><p className="mt-1 text-2xl font-extrabold">{outboundCount}</p></div>
        </section>

        <div className="mt-6 grid gap-5 lg:grid-cols-[250px_1fr]">
          <aside className="lg:sticky lg:top-24 lg:self-start">
            <form className="card grid gap-4 p-4" method="get">
              <div><p className="font-extrabold">Filtros</p><p className="muted mt-1 text-xs leading-5">Refine a caixa sem perder o contexto do atendimento.</p></div>
              <label className="field"><span>Canal</span><select name="canal" defaultValue={channel}><option value="">Todos</option><option value="email">E-mail</option><option value="whatsapp">WhatsApp</option></select></label>
              <label className="field"><span>Direção</span><select name="direcao" defaultValue={direction}><option value="">Todas</option><option value="inbound">Recebidas</option><option value="outbound">Enviadas</option></select></label>
              <button className="btn-primary w-full" type="submit">Aplicar filtros</button>
              {channel || direction ? <Link href="/atendimento" className="btn-ghost w-full">Limpar filtros</Link> : null}
            </form>
            <div className="soft-panel mt-3 p-4 text-xs leading-5 text-slate-500">
              <strong className="text-slate-700">Sobre os status:</strong> “Aceita pelo canal” não significa entregue. Entrega e leitura só aparecem quando o provider confirma por Webhook.
            </div>
          </aside>

          <section aria-label="Mensagens">
            {!emailAllowed && !whatsappAllowed ? (
              <div className="card p-6 sm:p-8">
                <p className="eyebrow">Recurso do plano</p>
                <h2 className="mt-4 text-xl font-extrabold">Nenhum canal de atendimento está habilitado</h2>
                <p className="muted mt-2 max-w-xl text-sm leading-6">Ative um plano com e-mail transacional ou WhatsApp oficial para centralizar mensagens aqui.</p>
                <Link href="/assinatura" className="btn-primary mt-5">Ver planos</Link>
              </div>
            ) : (
              <div className="grid gap-3">
                {messages.map((message) => {
                  const contact = message.lead_id ? leadNames.get(message.lead_id) : message.customer_id ? customerNames.get(message.customer_id) : null;
                  const href = message.lead_id ? `/crm/${message.lead_id}` : message.customer_id ? `/clientes/${message.customer_id}` : null;
                  const channelLabel = message.channel === "email" ? "E-mail" : "WhatsApp";
                  const directionLabel = message.direction === "inbound" ? "Recebida" : "Enviada";
                  const preview = message.template_name
                    ? `Template: ${message.template_name}${message.body ? `\n${message.body}` : ""}`
                    : (message.body || "[conteúdo não textual]");

                  return (
                    <article key={message.id} className="card overflow-hidden">
                      <div className="flex items-start gap-3 p-4 sm:p-5">
                        <div className={`mt-1 grid h-9 w-9 shrink-0 place-items-center rounded-xl text-xs font-extrabold ${message.channel === "whatsapp" ? "bg-emerald-50 text-emerald-700" : "bg-blue-50 text-blue-700"}`} aria-hidden="true">
                          {message.channel === "whatsapp" ? "WA" : "@"}
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                            <div className="min-w-0">
                              <div className="flex flex-wrap items-center gap-2">
                                <span className="text-xs font-extrabold text-slate-500">{channelLabel}</span>
                                <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[.68rem] font-bold text-slate-600">{directionLabel}</span>
                              </div>
                              <h2 className="mt-1 truncate font-extrabold text-slate-900">{contact || message.sender || message.recipient || "Contato"}</h2>
                              {message.subject ? <p className="mt-1 truncate text-sm font-semibold text-slate-600">{message.subject}</p> : null}
                            </div>
                            <div className="shrink-0 sm:text-right">
                              <p className="text-xs font-extrabold text-slate-700">{statusLabels[message.status] ?? message.status}</p>
                              <p className="muted mt-1 text-xs">{formatDate(message.created_at)}</p>
                            </div>
                          </div>
                          <p className="mt-3 line-clamp-4 whitespace-pre-wrap text-sm leading-6 text-slate-600">{preview}</p>
                          {href ? <Link className="mt-4 inline-flex text-sm font-extrabold text-blue-700" href={href}>{message.lead_id ? "Abrir lead →" : "Abrir cliente →"}</Link> : null}
                        </div>
                      </div>
                    </article>
                  );
                })}
                {messages.length === 0 ? (
                  <div className="card p-7 text-center sm:p-10">
                    <div className="mx-auto grid h-11 w-11 place-items-center rounded-2xl bg-slate-100 text-lg text-slate-400" aria-hidden="true">⋯</div>
                    <h2 className="mt-4 font-extrabold">Nenhuma mensagem encontrada</h2>
                    <p className="muted mx-auto mt-2 max-w-md text-sm leading-6">Quando um canal real enviar ou receber mensagens compatíveis com estes filtros, elas aparecerão aqui.</p>
                  </div>
                ) : null}
              </div>
            )}
          </section>
        </div>
      </main>
    </>
  );
}
