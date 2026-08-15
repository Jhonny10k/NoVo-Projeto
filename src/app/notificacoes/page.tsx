import Link from "next/link";
import { DashboardNav } from "@/components/dashboard/nav";
import { markAllNotificationsReadAction, markNotificationReadAction } from "@/features/notifications/actions";
import { requireUser } from "@/lib/auth/require-user";
import { formatDate } from "@/lib/format";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };
type Notification = { id: string; kind: string; title: string; body: string | null; entity_type: string | null; entity_id: string | null; read_at: string | null; created_at: string };

function entityHref(item: Notification) {
  if (item.entity_type === "subscription") return "/assinatura";
  if (!item.entity_id) return null;
  if (item.entity_type === "lead") return `/crm/${item.entity_id}`;
  if (item.entity_type === "customer") return `/clientes/${item.entity_id}`;
  if (item.entity_type === "quote") return `/orcamentos/${item.entity_id}`;
  return null;
}

export default async function NotificationsPage({ searchParams }: Props) {
  await requireUser();
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();
  const { data, error } = await supabase.from("notifications")
    .select("id,kind,title,body,entity_type,entity_id,read_at,created_at")
    .eq("organization_id", organization.id)
    .order("created_at", { ascending: false })
    .limit(200);
  const params = await searchParams;
  const success = params.status === "lidas";
  const items = (data ?? []) as Notification[];
  const unread = items.filter((item) => !item.read_at).length;

  return <><DashboardNav organizationName={organization.name} /><main className="container-shell py-10">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-bold uppercase tracking-widest text-blue-700">Notificações</p><h1 className="mt-1 text-3xl font-black">Central de atenção</h1><p className="muted mt-2">{unread} não lida{unread === 1 ? "" : "s"}. Eventos vêm de dados reais da organização.</p></div>{unread ? <form action={markAllNotificationsReadAction}><button className="btn-secondary" type="submit">Marcar todas como lidas</button></form> : null}</div>
    {success ? <p className="mt-5 rounded-xl bg-emerald-50 p-4 text-sm font-semibold">Notificações marcadas como lidas.</p> : null}
    {error ? <p role="alert" className="mt-5 rounded-xl bg-amber-50 p-4 text-sm">Não foi possível carregar as notificações.</p> : null}
    <section className="mt-7 grid gap-3">{items.map((item) => { const href = entityHref(item); return <article key={item.id} className={`card p-5 ${item.read_at ? "opacity-70" : "ring-1 ring-blue-200"}`}><div className="flex flex-wrap items-start justify-between gap-3"><div><div className="flex items-center gap-2"><span className="rounded-full bg-black/5 px-2 py-1 text-[11px] font-bold uppercase">{item.kind}</span><h2 className="font-black">{item.title}</h2></div>{item.body ? <p className="muted mt-2 text-sm">{item.body}</p> : null}<p className="muted mt-2 text-xs">{formatDate(item.created_at)}</p></div><div className="flex gap-2">{href ? <Link className="btn-secondary min-h-9" href={href}>Abrir</Link> : null}{!item.read_at ? <form action={markNotificationReadAction}><input type="hidden" name="notification_id" value={item.id} /><button className="btn-secondary min-h-9" type="submit">Marcar lida</button></form> : null}</div></div></article>; })}{items.length === 0 ? <div className="card p-6"><h2 className="font-bold">Tudo em dia.</h2><p className="muted mt-2">Novos pedidos, respostas de orçamento e mudanças relevantes aparecerão aqui.</p></div> : null}</section>
  </main></>;
}
