import Link from "next/link";
import { DashboardNav } from "@/components/dashboard/nav";
import { createTaskAction, deleteTaskAction, updateTaskStatusAction } from "@/features/tasks/actions";
import { requireUser } from "@/lib/auth/require-user";
import { formatDate } from "@/lib/format";
import { requireCurrentOrganization } from "@/lib/organizations/current";
import { hasFeature, requireFeature } from "@/lib/plans/entitlements";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };
type PersonOption = { id: string; name: string };
type UnitOption={id:string;name:string;code:string;is_headquarters:boolean};
type TaskRow = { id: string; unit_id:string|null; title: string; description: string | null; priority: string; due_at: string | null; status: string; lead_id: string | null; customer_id: string | null; created_at: string };

const statusLabel: Record<string, string> = { open: "Aberta", in_progress: "Em andamento", done: "Concluída", canceled: "Cancelada" };
const priorityLabel: Record<string, string> = { low: "Baixa", medium: "Média", high: "Alta", urgent: "Urgente" };

export default async function TasksPage({searchParams }: Props) {
  await requireFeature("tasks");
  const canExport = await hasFeature("exports");
  await requireUser();
  const organization = await requireCurrentOrganization();
  const supabase = await createClient();
  const [{ data: tasks }, { data: leads }, { data: customers }, {data:unitsData}] = await Promise.all([
    supabase.from("tasks").select("id,unit_id,title,description,priority,due_at,status,lead_id,customer_id,created_at").eq("organization_id", organization.id).order("status").order("due_at", { ascending: true, nullsFirst: false }).limit(300),
    supabase.from("leads").select("id,name").eq("organization_id", organization.id).order("name"),
    supabase.from("customers").select("id,name").eq("organization_id", organization.id).order("name"),
    supabase.rpc("list_accessible_units",{p_organization_id:organization.id})
  ]);
  const params = await searchParams;
  const error = typeof params.erro === "string" ? params.erro : "";
  const status = typeof params.status === "string" ? params.status : "";
  const canDelete = ["owner", "admin"].includes(organization.role);
  const units=(unitsData??[]) as UnitOption[];const unitNames=new Map(units.map(unit=>[unit.id,unit.name]));

  return <><DashboardNav organizationName={organization.name} /><main className="container-shell py-10">
    <div><p className="text-sm font-bold uppercase tracking-widest text-blue-700">Tarefas</p><h1 className="mt-1 text-3xl font-black">Próximas ações</h1><div className="mt-4">{canExport ? <Link href="/api/export/tasks" className="btn-secondary">Exportar tarefas</Link> : <Link href="/assinatura?recurso=exports" className="btn-secondary">Liberar exportação</Link>}</div><p className="muted mt-2">Vincule tarefas a leads ou clientes e acompanhe o andamento.</p></div>
    {status ? <p className="mt-5 rounded-xl bg-emerald-50 p-4 text-sm font-semibold">Tarefa criada.</p> : null}{error ? <p className="mt-5 rounded-xl bg-amber-50 p-4 text-sm">Não foi possível concluir a ação.</p> : null}
    <details className="card mt-7 p-5"><summary className="cursor-pointer font-bold">+ Nova tarefa</summary><form action={createTaskAction} className="mt-5 grid gap-4 md:grid-cols-2">
      <label className="field md:col-span-2"><span>Título</span><input name="title" minLength={2} required /></label>
      <label className="field md:col-span-2"><span>Descrição</span><textarea name="description" /></label>
      <label className="field"><span>Prioridade</span><select name="priority" defaultValue="medium"><option value="low">Baixa</option><option value="medium">Média</option><option value="high">Alta</option><option value="urgent">Urgente</option></select></label>
      <label className="field"><span>Prazo</span><input name="due_at" type="datetime-local" /></label>
      <label className="field"><span>Lead vinculado</span><select name="lead_id"><option value="">Nenhum</option>{((leads ?? []) as PersonOption[]).map((lead) => <option key={lead.id} value={lead.id}>{lead.name}</option>)}</select></label>
      <label className="field"><span>Cliente vinculado</span><select name="customer_id"><option value="">Nenhum</option>{((customers ?? []) as PersonOption[]).map((customer) => <option key={customer.id} value={customer.id}>{customer.name}</option>)}</select></label>
      {units.length?<label className="field"><span>Unidade</span><select name="unit_id" defaultValue=""><option value="">Escopo geral / herdar vínculo</option>{units.map(unit=><option key={unit.id} value={unit.id}>{unit.name} ({unit.code})</option>)}</select></label>:null}
      <button className="btn-primary md:w-fit" type="submit">Criar tarefa</button>
    </form></details>

    <section className="mt-8 grid gap-4 md:grid-cols-2 xl:grid-cols-3">{((tasks ?? []) as TaskRow[]).map((task) => <article key={task.id} className="card p-5">
      <div className="flex items-start justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-wide text-blue-700">{priorityLabel[task.priority] ?? task.priority}</p><h2 className="mt-1 font-black">{task.title}</h2>{task.unit_id?<p className="mt-1 text-xs font-bold text-blue-700">{unitNames.get(task.unit_id)??"Unidade"}</p>:null}</div><span className="rounded-full bg-black/5 px-3 py-1 text-xs font-semibold">{statusLabel[task.status] ?? task.status}</span></div>
      {task.description ? <p className="muted mt-3 text-sm">{task.description}</p> : null}<p className="mt-4 text-xs"><strong>Prazo:</strong> {formatDate(task.due_at)}</p>
      <form action={updateTaskStatusAction} className="mt-4 flex gap-2"><input type="hidden" name="task_id" value={task.id} /><select name="status" defaultValue={task.status} className="min-h-10 flex-1 rounded-lg border border-black/10 bg-white px-2 text-sm"><option value="open">Aberta</option><option value="in_progress">Em andamento</option><option value="done">Concluída</option><option value="canceled">Cancelada</option></select><button className="btn-secondary min-h-10" type="submit">Salvar</button></form>
      {canDelete ? <form action={deleteTaskAction} className="mt-2"><input type="hidden" name="task_id" value={task.id} /><button className="text-xs font-bold text-red-700" type="submit">Excluir tarefa</button></form> : null}
    </article>)}{(tasks ?? []).length === 0 ? <div className="card p-6"><h2 className="font-bold">Nenhuma tarefa.</h2><p className="muted mt-2">Crie uma tarefa para organizar os próximos passos comerciais.</p></div> : null}</section>
  </main></>;
}
