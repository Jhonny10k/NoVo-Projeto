import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Entity = "leads" | "customers" | "quotes" | "tasks";
const allowed = new Set<Entity>(["leads","customers","quotes","tasks"]);

function csvCell(value: unknown) {
  if (value === null || value === undefined) return "";
  let text = value instanceof Date ? value.toISOString() : String(value);
  if (/^[=+\-@\t\r]/.test(text)) text = `'${text}`;
  return `"${text.replace(/"/g,'""')}"`;
}

function toCsv(rows: Record<string,unknown>[], columns: Array<[string,string]>) {
  const header = columns.map(([label]) => csvCell(label)).join(";");
  const body = rows.map((row) => columns.map(([,key]) => csvCell(row[key])).join(";")).join("\r\n");
  return `\uFEFF${header}\r\n${body}`;
}

export async function GET(_request: Request, { params }: { params: Promise<{ entity: string }> }) {
  const { entity: rawEntity } = await params;
  if (!allowed.has(rawEntity as Entity)) return new Response("Exportação não encontrada.", { status: 404 });
  const entity = rawEntity as Entity;
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return new Response("Não autenticado.", { status: 401 });

  const { data: membership } = await supabase.from("organization_members").select("organization_id").eq("user_id",auth.user.id).eq("status","active").order("created_at").limit(1).maybeSingle();
  if (!membership?.organization_id) return new Response("Organização não encontrada.", { status: 404 });
  const { data: canExport } = await supabase.rpc("has_feature", { p_organization_id: membership.organization_id, p_feature: "exports" });
  if (canExport !== true) return new Response("Seu plano não inclui exportações.", { status: 403 });

  let rows: Record<string,unknown>[] = [];
  let columns: Array<[string,string]> = [];
  if (entity === "leads") {
    const { data, error } = await supabase.from("leads").select("name,phone,whatsapp,email,company,source,status,interest,potential_value_cents,last_contact_at,next_contact_at,created_at").eq("organization_id",membership.organization_id).order("created_at",{ascending:false}).limit(10000);
    if (error) return new Response("Falha ao exportar leads.",{status:500});
    rows = data ?? []; columns = [["Nome","name"],["Telefone","phone"],["WhatsApp","whatsapp"],["E-mail","email"],["Empresa","company"],["Origem","source"],["Status","status"],["Interesse","interest"],["Valor potencial (centavos)","potential_value_cents"],["Último contato","last_contact_at"],["Próximo contato","next_contact_at"],["Criado em","created_at"]];
  } else if (entity === "customers") {
    const { data, error } = await supabase.from("customers").select("name,phone,whatsapp,email,company,created_at").eq("organization_id",membership.organization_id).order("created_at",{ascending:false}).limit(10000);
    if (error) return new Response("Falha ao exportar clientes.",{status:500});
    rows = data ?? []; columns = [["Nome","name"],["Telefone","phone"],["WhatsApp","whatsapp"],["E-mail","email"],["Empresa","company"],["Criado em","created_at"]];
  } else if (entity === "quotes") {
    const { data, error } = await supabase.from("quotes").select("number,status,subtotal_cents,discount_cents,fee_cents,total_cents,valid_until,created_at").eq("organization_id",membership.organization_id).order("created_at",{ascending:false}).limit(10000);
    if (error) return new Response("Falha ao exportar orçamentos.",{status:500});
    rows = data ?? []; columns = [["Número","number"],["Status","status"],["Subtotal (centavos)","subtotal_cents"],["Desconto (centavos)","discount_cents"],["Taxa (centavos)","fee_cents"],["Total (centavos)","total_cents"],["Validade","valid_until"],["Criado em","created_at"]];
  } else {
    const { data, error } = await supabase.from("tasks").select("title,description,priority,due_at,status,created_at").eq("organization_id",membership.organization_id).order("created_at",{ascending:false}).limit(10000);
    if (error) return new Response("Falha ao exportar tarefas.",{status:500});
    rows = data ?? []; columns = [["Título","title"],["Descrição","description"],["Prioridade","priority"],["Prazo","due_at"],["Status","status"],["Criado em","created_at"]];
  }

  const filename = `${entity}-${new Date().toISOString().slice(0,10)}.csv`;
  return new Response(toCsv(rows,columns), { headers: { "Content-Type":"text/csv; charset=utf-8", "Content-Disposition":`attachment; filename="${filename}"`, "Cache-Control":"private, no-store" } });
}
