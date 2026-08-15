import { formatDate } from "@/lib/format";

type TimelineEvent = {
  id: string;
  event_type: string;
  metadata: Record<string, unknown> | null;
  created_at: string;
};

const labels: Record<string, string> = {
  lead_created: "Lead criado",
  quote_request_received: "Pedido de orçamento recebido",
  lead_stage_changed: "Etapa do CRM alterada",
  lead_converted_to_customer: "Lead convertido em cliente",
  quote_created: "Orçamento criado",
  quote_link_enabled: "Link do orçamento liberado",
  quote_viewed: "Orçamento visualizado",
  quote_response: "Resposta do orçamento",
  subscription_status_changed: "Assinatura atualizada"
};

function detail(event: TimelineEvent) {
  const metadata = event.metadata ?? {};
  if (event.event_type === "lead_stage_changed" && typeof metadata.stage_key === "string") return `Nova etapa: ${metadata.stage_key}`;
  if (event.event_type === "quote_response" && typeof metadata.status === "string") return `Resposta: ${metadata.status}`;
  if (event.event_type === "quote_request_received" && typeof metadata.source === "string") return `Origem: ${metadata.source}`;
  if (event.event_type === "subscription_status_changed" && typeof metadata.status === "string") return `Status: ${metadata.status}`;
  return null;
}

export function EventTimeline({ events }: { events: TimelineEvent[] }) {
  if (!events.length) return <div className="rounded-xl border border-dashed border-black/10 p-5"><p className="font-semibold">Nenhuma atividade registrada.</p><p className="muted mt-1 text-sm">As próximas interações aparecerão nesta linha do tempo.</p></div>;

  return <ol className="grid gap-3">{events.map((event) => <li key={event.id} className="relative rounded-xl border border-black/5 bg-white p-4 pl-5"><span className="absolute left-0 top-5 h-2 w-2 -translate-x-1/2 rounded-full bg-blue-600" /><div className="flex flex-wrap items-start justify-between gap-2"><div><p className="font-bold">{labels[event.event_type] ?? event.event_type.replaceAll("_", " ")}</p>{detail(event) ? <p className="muted mt-1 text-sm">{detail(event)}</p> : null}</div><time className="muted text-xs">{formatDate(event.created_at)}</time></div></li>)}</ol>;
}
